# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::LostMessagesReconciliationService do
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
        'api_key' => 'TEST-KEY',
        'base_url' => 'http://localhost:8080',
        'sync_lost_messages' => true,
        'connection_status' => 'open'
      )
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    allow(api_client).to receive(:connection_state).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'instance' => { 'state' => 'open' } }
      )
    )
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
    allow(api_client).to receive(:find_messages).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'messages' => {
            'records' => [],
            'pages' => 1
          }
        }
      )
    )
  end

  it 'skips reconciliation when sync_lost_messages is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_lost_messages' => false)
    )

    expect(api_client).not_to receive(:find_messages)
    described_class.new(channel: channel).perform
  end

  it 'queries Evolution when sync is enabled and connection is open' do
    expect(api_client).to receive(:find_messages).once
    described_class.new(channel: channel).perform
  end

  it 'imports the same missing message only once even when Evolution returns duplicates' do
    duplicate_payload = {
      'key' => {
        'id' => 'EVO-DUP-1',
        'remoteJid' => '5511999999999@s.whatsapp.net',
        'fromMe' => false
      },
      'messageType' => 'conversation',
      'message' => { 'conversation' => 'hello' },
      'pushName' => 'Alice',
      'messageTimestamp' => Time.current.to_i
    }
    normalized_payload = {
      contacts: [{ profile: { name: 'Alice' }, wa_id: '5511999999999' }],
      messages: [{ from: '5511999999999', id: 'EVO-DUP-1', timestamp: Time.current.to_i.to_s, type: 'text', text: { body: 'hello' } }]
    }
    normalizer = instance_double(Custom::Whatsapp::Webhooks::EvolutionNormalizer, perform: normalized_payload)
    incoming_service = instance_double(Whatsapp::IncomingMessageService, perform: true)

    allow(api_client).to receive(:find_messages).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: {
          'messages' => {
            'records' => [duplicate_payload, duplicate_payload],
            'pages' => 1
          }
        }
      )
    )
    allow(Custom::Whatsapp::Webhooks::EvolutionNormalizer).to receive(:new).and_return(normalizer)
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_return(incoming_service)

    described_class.new(channel: channel).perform

    expect(Whatsapp::IncomingMessageService).to have_received(:new).once
    expect(incoming_service).to have_received(:perform).once
  end
end
