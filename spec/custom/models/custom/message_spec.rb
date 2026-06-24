# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message, type: :model do
  def build_evolution_inbox(account, provider_config: {}, lock_to_single: true)
    channel = create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
        {
          'instance_name' => 'test-instance',
          'api_key' => 'TEST-KEY',
          'base_url' => 'http://localhost:8080'
        }.merge(provider_config.stringify_keys)
      )
    )
    inbox = channel.inbox
    inbox.update!(lock_to_single_conversation: lock_to_single)
    inbox
  end

  let(:account) { create(:account) }

  describe 'Evolution conversation reopen' do
    let(:inbox) { build_evolution_inbox(account, provider_config: { 'conversation_pending' => true }) }
    let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }

    it 'reopens resolved conversation as pending when conversation_pending is enabled' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved
      )

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      expect(conversation.reload).to be_pending
      expect(conversation.additional_attributes['evolution_pending_since']).to be_present
    end

    it 'opens pending conversation on the second customer message' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :pending,
        additional_attributes: { evolution_pending_since: 1.hour.ago.utc.iso8601(3) }
      )
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      expect(conversation.reload).to be_open
    end

    it 'reopens snoozed conversation as pending without lock_to_single when conversation_pending is enabled' do
      inbox = build_evolution_inbox(account, provider_config: { 'conversation_pending' => true }, lock_to_single: false)
      snoozed_contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511888888888')
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: snoozed_contact_inbox,
        status: :snoozed
      )

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      expect(conversation.reload).to be_pending
    end

    it 'reopens resolved conversation as pending without lock_to_single when conversation_pending is enabled' do
      inbox = build_evolution_inbox(account, provider_config: { 'conversation_pending' => true }, lock_to_single: false)
      resolved_contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511777777777')
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: resolved_contact_inbox,
        status: :resolved
      )

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      expect(conversation.reload).to be_pending
      expect(conversation.additional_attributes['evolution_pending_since']).to be_present
    end
  end
end
