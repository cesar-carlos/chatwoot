# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Webhooks::EvolutionGoNormalizer do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'instance_name' => 'test-go-instance',
        'instance_token' => 'token'
      )
    )
  end
  let(:fixture) do
    JSON.parse(Rails.root.join('spec/fixtures/evolution_go/message_inbound.json').read)
  end

  it 'normalizes inbound text MESSAGE events from Info/Message payloads' do
    result = described_class.new(channel, fixture).perform

    expect(result[:contacts].first[:wa_id]).to eq('5511999999999')
    expect(result[:messages].first[:id]).to eq('3EB0C5A277F7F9B6C599')
    expect(result[:messages].first[:text][:body]).to eq('Olá from Evolution Go!')
  end

  it 'normalizes legacy key/message payloads' do
    legacy_fixture = {
      'event' => 'MESSAGE',
      'data' => {
        'key' => {
          'remoteJid' => '5511999999999@s.whatsapp.net',
          'fromMe' => false,
          'id' => 'LEGACY1'
        },
        'message' => { 'conversation' => 'Legacy hello' }
      }
    }

    result = described_class.new(channel, legacy_fixture).perform

    expect(result[:messages].first[:id]).to eq('LEGACY1')
    expect(result[:messages].first[:text][:body]).to eq('Legacy hello')
  end

  it 'filters fromMe echo messages' do
    payload = fixture.deep_dup
    payload['data']['Info']['IsFromMe'] = true

    expect(described_class.new(channel, payload).perform).to be_nil
  end

  it 'allows fromMe when ignore_from_me_echo is false' do
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_from_me_echo' => false)
    )
    payload = fixture.deep_dup
    payload['data']['Info']['IsFromMe'] = true

    expect(described_class.new(channel, payload).perform).to be_present
  end

  it 'filters group messages when ignore_groups is true' do
    payload = fixture.deep_dup
    payload['data']['Info']['Chat'] = '120363012345678901@g.us'
    payload['data']['Info']['Sender'] = '120363012345678901@g.us'

    expect(described_class.new(channel, payload).perform).to be_nil
  end

  it 'normalizes group messages when ignore_groups is false' do
    allow(Custom::Whatsapp::Evolution::GroupMetadataService).to receive(:new).and_return(
      instance_double(Custom::Whatsapp::Evolution::GroupMetadataService, display_name: 'Support Team (GROUP)')
    )
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_groups' => false)
    )
    group_fixture = JSON.parse(
      Rails.root.join('spec/fixtures/evolution_go/message_inbound_group.json').read
    )

    result = described_class.new(channel, group_fixture).perform

    aggregate_failures do
      expect(result.dig(:contacts, 0, :wa_id)).to eq('120363012345678901@g.us')
      expect(result.dig(:contacts, 0, :profile, :name)).to eq('Support Team (GROUP)')
      expect(result.dig(:messages, 0, :id)).to eq('3EB0GROUP00000001')
      expect(result.dig(:messages, 0, :text, :body)).to eq('Hello from the group!')
      expect(result.dig(:messages, 0, :evolution_go_remote_jid)).to eq('120363012345678901@g.us')
      expect(result.dig(:messages, 0, :evolution_go_participant_jid)).to eq('5511777777777:38@s.whatsapp.net')
    end
  end

  it 'normalizes legacy group key payloads when ignore_groups is false' do
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_groups' => false)
    )
    legacy_group_fixture = {
      'event' => 'MESSAGE',
      'data' => {
        'key' => {
          'remoteJid' => '120363012345678901@g.us',
          'participant' => '5511777777777@s.whatsapp.net',
          'fromMe' => false,
          'id' => 'LEGACYGROUP1'
        },
        'message' => { 'conversation' => 'Legacy group hello' },
        'pushName' => 'Group Member'
      }
    }

    result = described_class.new(channel, legacy_group_fixture).perform

    aggregate_failures do
      expect(result.dig(:contacts, 0, :wa_id)).to eq('120363012345678901@g.us')
      expect(result.dig(:messages, 0, :id)).to eq('LEGACYGROUP1')
      expect(result.dig(:messages, 0, :text, :body)).to eq('Legacy group hello')
      expect(result.dig(:messages, 0, :evolution_go_remote_jid)).to eq('120363012345678901@g.us')
      expect(result.dig(:messages, 0, :evolution_go_participant_jid)).to eq('5511777777777@s.whatsapp.net')
    end
  end

  it 'prefers Info.Chat group JID when key.remoteJid is the participant' do
    channel.update!(
      provider_config: channel.provider_config.merge('ignore_groups' => false)
    )
    mixed_fixture = {
      'event' => 'MESSAGE',
      'data' => {
        'Info' => {
          'ID' => 'MIXEDGROUP1',
          'Chat' => '120363012345678901@g.us',
          'Sender' => '5511777777777@s.whatsapp.net',
          'SenderAlt' => '5511777777777@s.whatsapp.net',
          'IsFromMe' => false,
          'PushName' => 'Group Member',
          'Timestamp' => 1699999999
        },
        'Message' => { 'conversation' => 'Mixed payload hello' },
        'key' => {
          'remoteJid' => '5511777777777@s.whatsapp.net',
          'fromMe' => false,
          'id' => 'WRONGKEY1'
        }
      }
    }

    result = described_class.new(channel, mixed_fixture).perform

    aggregate_failures do
      expect(result.dig(:contacts, 0, :wa_id)).to eq('120363012345678901@g.us')
      expect(result.dig(:messages, 0, :evolution_go_remote_jid)).to eq('120363012345678901@g.us')
      expect(result.dig(:messages, 0, :evolution_go_participant_jid)).to eq('5511777777777@s.whatsapp.net')
    end
  end

  it 'normalizes inbound image MESSAGE events' do
    image_fixture = JSON.parse(
      Rails.root.join('spec/fixtures/evolution_go/message_inbound_image.json').read
    )
    result = described_class.new(channel, image_fixture).perform

    expect(result[:messages].first[:type]).to eq('image')
    expect(result[:messages].first[:image][:_evolution_go_message]).to be_present
    expect(result[:messages].first[:image][:caption]).to eq('Photo caption')
  end

  it 'normalizes inbound location MESSAGE events' do
    location_fixture = JSON.parse(
      Rails.root.join('spec/fixtures/evolution_go/message_inbound_location.json').read
    )

    result = described_class.new(channel, location_fixture).perform

    aggregate_failures do
      expect(result[:messages].first[:type]).to eq('location')
      expect(result[:messages].first[:location][:latitude]).to eq(-23.5505199)
      expect(result[:messages].first[:location][:longitude]).to eq(-46.6333094)
      expect(result[:messages].first[:location][:name]).to eq('São Paulo')
    end
  end

  it 'renders reaction messages as placeholder text' do
    reaction_fixture = {
      'event' => 'MESSAGE',
      'data' => {
        'key' => {
          'remoteJid' => '5511999999999@s.whatsapp.net',
          'fromMe' => false,
          'id' => 'REACTION1'
        },
        'message' => { 'reactionMessage' => { 'text' => '👍' } }
      }
    }

    result = described_class.new(channel, reaction_fixture).perform

    expect(result[:messages].first[:text][:body]).to eq('[Reaction message]')
  end
end
