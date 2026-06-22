# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::DeleteSyncService do
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
        'sync_delete_to_whatsapp' => true
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'MSG123',
      content_attributes: { deleted: true }
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::Evolution::ApiClient) }

  before do
    allow(Custom::Whatsapp::Evolution::ApiClient).to receive(:for_channel).and_return(api_client)
    allow(api_client).to receive(:delete_message_for_everyone)
  end

  it 'calls Evolution delete endpoint when enabled' do
    success_response = instance_double(HTTParty::Response, success?: true)
    allow(api_client).to receive(:delete_message_for_everyone).and_return(success_response)

    described_class.new(message: message).perform

    expect(api_client).to have_received(:delete_message_for_everyone).with(
      id: 'MSG123',
      remote_jid: '5511999999999@s.whatsapp.net',
      from_me: true
    )
  end

  it 'logs when Evolution delete endpoint returns a non-success response' do
    failed_response = instance_double(HTTParty::Response, success?: false, code: 500)
    allow(api_client).to receive(:delete_message_for_everyone).and_return(failed_response)
    allow(Rails.logger).to receive(:warn)

    described_class.new(message: message).perform

    expect(Rails.logger).to have_received(:warn).with(
      "[EVOLUTION] delete sync HTTP 500 for message #{message.id}"
    )
  end

  it 'skips when sync_delete_to_whatsapp is disabled' do
    channel.update!(
      provider_config: channel.provider_config.merge('sync_delete_to_whatsapp' => false)
    )

    described_class.new(message: message).perform

    expect(api_client).not_to have_received(:delete_message_for_everyone)
  end

  it 'uses evolution_remote_jid from content_attributes when present' do
    message.update!(content_attributes: { deleted: true, evolution_remote_jid: '242532642504895@lid' })
    success_response = instance_double(HTTParty::Response, success?: true)
    allow(api_client).to receive(:delete_message_for_everyone).and_return(success_response)

    described_class.new(message: message).perform

    expect(api_client).to have_received(:delete_message_for_everyone).with(
      id: 'MSG123',
      remote_jid: '242532642504895@lid',
      from_me: true
    )
  end
end
