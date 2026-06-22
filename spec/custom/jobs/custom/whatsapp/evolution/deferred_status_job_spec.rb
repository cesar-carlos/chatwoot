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
end
