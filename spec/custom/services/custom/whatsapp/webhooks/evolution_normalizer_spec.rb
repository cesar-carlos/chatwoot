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

  describe '#perform' do
    it 'normalizes MESSAGES_UPSERT text from fixture' do
      envelope = load_fixture('messages_upsert_text')
      expected = load_fixture('messages_upsert_text_normalized')

      result = normalize(envelope)

      expect(result.deep_stringify_keys).to eq(expected)
    end

    it 'maps MESSAGES_UPDATE status to read' do
      envelope = load_fixture('messages_update_read')

      result = normalize(envelope)

      aggregate_failures do
        expect(result[:statuses].size).to eq(1)
        expect(result[:statuses].first[:id]).to eq('3EB0OUTBOUND987654')
        expect(result[:statuses].first[:status]).to eq('read')
        expect(result[:statuses].first[:recipient_id]).to eq('5511999999999')
      end
    end

    it 'ignores fromMe messages when ignore_from_me_echo is enabled' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['fromMe'] = true

      expect(normalize(envelope)).to be_nil
    end

    it 'ignores group messages when groups_ignore is enabled' do
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['remoteJid'] = '120363123456789012@g.us'
      envelope['data']['key'].delete('remoteJidAlt')
      envelope['data']['key'].delete('addressingMode')

      expect(normalize(envelope)).to be_nil
    end

    it 'ignores remote jids matching ignore_jids patterns' do
      channel.update!(
        provider_config: channel.provider_config.merge(
          'ignore_jids' => ['no-reply@'],
          'groups_ignore' => false
        )
      )
      envelope = load_fixture('messages_upsert_text')
      envelope['data']['key']['remoteJid'] = 'no-reply@newsletter'
      envelope['data']['key'].delete('remoteJidAlt')
      envelope['data']['key'].delete('addressingMode')

      expect(normalize(envelope)).to be_nil
    end
  end
end
