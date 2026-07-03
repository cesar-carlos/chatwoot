# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::DeferredStatusJob, type: :job do
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
        'api_key' => 'TEST-KEY'
      )
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let!(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      sender: contact,
      source_id: 'STATUS-MSG-1',
      status: :sent
    )
  end

  it 'applies a deferred delivered status update' do
    described_class.perform_now(inbox.id, { 'id' => 'STATUS-MSG-1', 'status' => 'delivered' })

    expect(message.reload.status).to eq('delivered')
  end

  it 'logs when deferred status retries are exhausted' do
    allow(Whatsapp::IncomingMessageService).to receive(:new).and_raise(StandardError, 'message not found')
    allow(Rails.logger).to receive(:warn)

    perform_enqueued_jobs(only: described_class) do
      described_class.perform_later(inbox.id, { 'id' => 'MISSING', 'status' => 'delivered' })
    end

    expect(Rails.logger).to have_received(:warn).with(
      a_string_matching(/\[EVOLUTION\] deferred status dropped inbox=#{inbox.id}/)
    )
  end
end
