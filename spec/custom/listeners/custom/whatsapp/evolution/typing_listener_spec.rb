# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::Evolution::TypingListener do
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
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:listener) { described_class.instance }

  it 'enqueues presence sync on typing on' do
    event = Events::Base.new('conversation.typing_on', Time.zone.now, conversation: conversation, is_private: false)

    expect(Custom::Whatsapp::Evolution::PresenceSyncJob).to receive(:perform_later).with(
      conversation.id, true, false
    )

    listener.conversation_typing_on(event)
  end

  it 'skips private note typing' do
    event = Events::Base.new('conversation.typing_on', Time.zone.now, conversation: conversation, is_private: true)

    expect(Custom::Whatsapp::Evolution::PresenceSyncJob).not_to receive(:perform_later)

    listener.conversation_typing_on(event)
  end
end
