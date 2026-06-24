# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionNormalizer do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        'instance_name' => 'test-instance',
        'api_key' => 'TEST-INSTANCE-API-KEY'
      )
    )
  end

  def load_fixture(name)
    JSON.parse(Rails.root.join("spec/fixtures/evolution/#{name}.json").read)
  end

  def normalize(envelope)
    described_class.new(channel: channel, envelope: envelope).perform
  end

  def apply_provider_config!(channel, attrs)
    channel.provider_config = channel.provider_config.merge(attrs)
    channel.save!(validate: false)
    channel.reload
  end

  describe '#perform' do
    it 'normalizes MESSAGES_UPSERT text from fixture' do
      envelope = load_fixture('messages_upsert_text')
      expected = load_fixture('messages_upsert_text_normalized')

      result = normalize(envelope)

      expect(result.deep_stringify_keys).to eq(expected)
    end

    it 'maps MESSAGES_UPDATE Evolution flat payload to read' do
      envelope = load_fixture('messages_update_read')

      result = normalize(envelope)

      aggregate_failures do
        expect(result[:statuses].size).to eq(1)
        expect(result[:statuses].first[:id]).to eq('3EB0OUTBOUND987654')
        expect(result[:statuses].first[:status]).to eq('read')
        expect(result[:statuses].first[:recipient_id]).to eq('5511999999999')
      end
    end

    it 'maps MESSAGES_UPDATE DELIVERY_ACK to delivered' do
      envelope = load_fixture('messages_update_delivered')

      result = normalize(envelope)

      expect(result[:statuses].first[:status]).to eq('delivered')
    end

    it 'maps Baileys numeric status codes correctly' do
      envelope = {
        'event' => 'MESSAGES_UPDATE',
        'data' => {
          'key' => { 'id' => 'BAILEYS123', 'remoteJid' => '5511999999999@s.whatsapp.net', 'fromMe' => true },
          'update' => { 'status' => 3 }
        }
      }

      expect(normalize(envelope)[:statuses].first[:status]).to eq('delivered')

      envelope['data']['update']['status'] = 4
      expect(normalize(envelope)[:statuses].first[:status]).to eq('read')
    end

    it 'resolves wa_id from remoteJidAlt when remoteJid ends with @lid without addressingMode' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key'].delete('addressingMode')

      result = normalize(envelope)

      aggregate_failures do
        expect(result.dig(:contacts, 0, :wa_id)).to eq('5566996971841')
        expect(result.dig(:messages, 0, :from)).to eq('5566996971841')
      end
    end

    it 'ignores fromMe messages when ignore_from_me_echo is enabled' do
      channel.update!(provider_config: channel.provider_config.merge('ignore_from_me_echo' => true))
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['fromMe'] = true

      expect(normalize(envelope)).to be_nil
    end

    it 'includes fromMe messages in import_mode' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['fromMe'] = true

      result = described_class.new(channel: channel, envelope: envelope, import_mode: true).perform

      expect(result).to be_present
      expect(result[:messages].first[:id]).to eq(envelope.dig('data', 'key', 'id'))
    end

    it 'ignores group messages when groups_ignore is enabled' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['remoteJid'] = '120363123456789012@g.us'
      envelope['data']['key'].delete('remoteJidAlt')
      envelope['data']['key'].delete('addressingMode')

      expect(normalize(envelope)).to be_nil
    end

    it 'normalizes group messages when groups_ignore is disabled' do
      allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
        instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Team (GROUP)')
      )
      apply_provider_config!(
        channel,
        'groups_ignore' => false,
        'ignore_jids' => [],
        'format_group_messages' => true
      )
      envelope = load_fixture('messages_upsert_group')

      result = normalize(envelope)

      aggregate_failures do
        expect(result.dig(:contacts, 0, :wa_id)).to eq('120363123456789012@g.us')
        expect(result.dig(:messages, 0, :text, :body)).to include('**Group Member:**')
        expect(result.dig(:messages, 0, :text, :body)).to include('Hello group')
      end
    end

    it 'ignores remote jids matching ignore_jids patterns' do
      apply_provider_config!(
        channel,
        'ignore_jids' => ['no-reply@'],
        'groups_ignore' => false
      )
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['remoteJid'] = 'no-reply@newsletter'
      envelope['data']['key'].delete('remoteJidAlt')
      envelope['data']['key'].delete('addressingMode')

      expect(normalize(envelope)).to be_nil
    end

    it 'ignores survey response links when ignore_survey_links is enabled' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['message']['conversation'] =
        'Please rate us https://app.example.com/survey/responses/abc123'

      expect(normalize(envelope)).to be_nil
    end

    it 'normalizes unsupported message types as placeholder text' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['message'] = { 'reactionMessage' => { 'text' => '👍' } }
      envelope['data']['messageType'] = 'reactionMessage'

      result = normalize(envelope)

      expect(result.dig(:messages, 0, :text, :body)).to eq('[Reaction message]')
    end

    it 'unwraps ephemeral messages before normalization' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['message'] = {
        'ephemeralMessage' => {
          'message' => { 'conversation' => 'Secret text' }
        }
      }
      envelope['data']['messageType'] = 'ephemeralMessage'

      result = normalize(envelope)

      expect(result.dig(:messages, 0, :text, :body)).to eq('Secret text')
    end
  end
end
