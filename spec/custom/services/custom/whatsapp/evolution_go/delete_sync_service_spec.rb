# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::DeleteSyncService do
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
        'instance_token' => 'TEST-TOKEN',
        'base_url' => 'https://evogo.example.com',
        'sync_delete_to_whatsapp' => true
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511888888888') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'OUT-MSG-1',
      content: 'hello',
      content_attributes: { evolution_go_remote_jid: '5511999999999@s.whatsapp.net' }
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }
  let(:response) { instance_double(HTTParty::Response, success?: true, code: 200) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).with(channel).and_return(api_client)
  end

  it 'calls Evolution Go delete API when enabled' do
    expect(api_client).to receive(:delete_message).with(
      chat: '5511999999999@s.whatsapp.net',
      message_id: 'OUT-MSG-1'
    ).and_return(response)

    described_class.new(message: message).perform
  end

  it 'reverts local soft-delete when WhatsApp API fails' do
    failed = instance_double(HTTParty::Response, success?: false, code: 400, parsed_response: { 'error' => 'too late' })
    allow(api_client).to receive(:delete_message).and_return(failed)
    message.update_columns(
      content_attributes: message.content_attributes.merge('deleted' => true, 'deleted_at' => Time.current.iso8601)
    )

    expect(described_class.new(message: message.reload).perform).to be(false)
    expect(message.reload.content_attributes['deleted']).not_to be(true)
  end

  it 'raises when raise_errors is true and API fails' do
    failed = instance_double(HTTParty::Response, success?: false, code: 400, parsed_response: {})
    allow(api_client).to receive(:delete_message).and_return(failed)
    message.update_columns(content_attributes: message.content_attributes.merge('deleted' => true))

    expect do
      described_class.new(message: message.reload, raise_errors: true).perform
    end.to raise_error(Custom::Whatsapp::EvolutionGo::ApiError)
    expect(message.reload.content_attributes['deleted']).not_to be(true)
  end

  it 'resolves LID chat jid from contact additional_attributes' do
    contact.update!(
      additional_attributes: {
        Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY => '123456789012345@lid'
      }
    )
    lid_message = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'OUT-LID-1',
      content: 'hello'
    )

    expect(api_client).to receive(:delete_message).with(
      chat: '123456789012345@lid',
      message_id: 'OUT-LID-1'
    ).and_return(response)

    described_class.new(message: lid_message).perform
  end

  it 'skips incoming messages' do
    incoming = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      source_id: 'IN-MSG-1',
      content: 'hello'
    )

    expect(api_client).not_to receive(:delete_message)

    described_class.new(message: incoming).perform
  end

  it 'skips when sync_delete_to_whatsapp is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_delete_to_whatsapp' => false)
    )

    expect(api_client).not_to receive(:delete_message)

    described_class.new(message: message).perform
  end
end
