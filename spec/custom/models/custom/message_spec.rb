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

  describe 'Wavoip voice call conversation cycle' do
    let(:channel) { create(:channel_wavoip, account: account) }
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: account, phone_number: '+5511999999999') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999999') }

    before do
      account.enable_features!('channel_voice', 'channel_wavoip')
    end

    def create_voice_call_message(conversation, direction: :incoming)
      call = create(
        :call,
        account: account,
        inbox: inbox,
        conversation: conversation,
        contact: contact,
        provider: :wavoip,
        direction: direction,
        status: 'ringing',
        provider_call_id: SecureRandom.uuid
      )
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: direction == :incoming ? :incoming : :outgoing,
        content_type: :voice_call,
        sender: direction == :incoming ? contact : create(:user, account: account),
        content_attributes: { data: { call_id: call.id, status: 'ringing' } }
      )
    end

    it 'reopens a resolved conversation as open on inbound voice call' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved
      )

      create_voice_call_message(conversation, direction: :incoming)

      expect(conversation.reload).to be_open
    end

    it 'reopens a resolved conversation as open on outbound voice call' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved
      )

      create_voice_call_message(conversation, direction: :outgoing)

      expect(conversation.reload).to be_open
    end

    it 'creates an open conversation for the first inbound voice call' do
      event = Voice::Dto::WebhookCallEvent.new(
        provider: :wavoip,
        external_call_id: 'wavoip_pending_cycle',
        action: :create,
        external_status: 'INCOMING_RING',
        direction: :incoming,
        from_phone: contact.phone_number,
        to_phone: channel.phone_number,
        peer_name: 'Caller',
        duration_seconds: nil,
        session_id: 1,
        call_type: :official,
        record_url: nil,
        record_status: nil,
        raw_type: 'CALL'
      )

      call = Wavoip::Calls::ConversationLinker.link_inbound!(inbox: inbox, event: event)

      expect(call.conversation).to be_open
    end

    it 'reuses the latest resolved conversation even when lock_to_single is disabled' do
      inbox.update!(lock_to_single_conversation: false)
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved
      )

      event = Voice::Dto::WebhookCallEvent.new(
        provider: :wavoip,
        external_call_id: 'wavoip_force_single_history',
        action: :create,
        external_status: 'INCOMING_RING',
        direction: :incoming,
        from_phone: contact.phone_number,
        to_phone: channel.phone_number,
        peer_name: 'Caller',
        duration_seconds: nil,
        session_id: 2,
        call_type: :official,
        record_url: nil,
        record_status: nil,
        raw_type: 'CALL'
      )

      call = Wavoip::Calls::ConversationLinker.link_inbound!(inbox: inbox, event: event)

      aggregate_failures do
        expect(call.conversation_id).to eq(conversation.id)
        expect(call.conversation).to be_open
        expect(Conversation.where(contact_inbox: contact_inbox).count).to eq(1)
      end
    end
  end
end
