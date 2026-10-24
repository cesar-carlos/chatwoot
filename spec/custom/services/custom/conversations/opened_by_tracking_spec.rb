# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass -- integration coverage for opened_by stamping
RSpec.describe 'Conversation opened_by tracking' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  describe 'Conversations::Resolver create' do
    it 'stamps opened_by from Current on create' do
      Current.conversation_opened_by = Custom::Conversations::OpenedByStamper::CONTACT

      conversation = Conversations::Resolver.new(
        inbox: inbox,
        contact_inbox: contact_inbox,
        conversation_params: {
          account_id: account.id,
          inbox_id: inbox.id,
          contact_id: contact.id,
          contact_inbox_id: contact_inbox.id
        }
      ).perform

      expect(conversation.additional_attributes['opened_by']).to eq('contact')
    ensure
      Current.reset
    end

    it 'stamps phone when passed in create params' do
      conversation = Conversations::Resolver.new(
        inbox: inbox,
        contact_inbox: contact_inbox,
        conversation_params: {
          account_id: account.id,
          inbox_id: inbox.id,
          contact_id: contact.id,
          contact_inbox_id: contact_inbox.id,
          additional_attributes: { 'opened_by' => 'phone' }
        }
      ).perform

      expect(conversation.additional_attributes['opened_by']).to eq('phone')
    end
  end

  describe 'incoming message reopen' do
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
    end

    it 'stamps opened_by=contact before reopen' do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        content: 'oi'
      )

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
    end

    it 'keeps opened_by=phone when the contact replies during a pending phone episode' do
      conversation.update!(status: :pending, additional_attributes: { 'opened_by' => 'phone' })

      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        content: 'oi'
      )

      expect(conversation.reload).to be_pending
      expect(conversation.additional_attributes['opened_by']).to eq('phone')
    end

    it 'stamps opened_by=contact when the contact reopens a resolved phone episode' do
      conversation.update!(additional_attributes: { 'opened_by' => 'phone' })

      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        sender: contact,
        content: 'oi'
      )

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
    end
  end

  describe 'agent toggle_status reopen' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
    end

    it 'stamps opened_by=agent' do
      Current.user = admin
      Current.account = account

      controller = Api::V1::Accounts::ConversationsController.new
      allow(controller).to receive_messages(
        params: ActionController::Parameters.new(status: 'open'),
        conversation: conversation
      )
      controller.instance_variable_set(:@conversation, conversation)

      controller.send(:stamp_opened_by_agent_on_reopen!)

      expect(conversation.reload.additional_attributes['opened_by']).to eq('agent')
    ensure
      Current.reset
    end
  end

  describe 'Wavoip::Calls::ConversationReopenService' do
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
    end

    before do
      allow(inbox).to receive(:channel).and_return(Channel::Wavoip.new)
    end

    it 'stamps contact when reopening as pending (inbound call)' do
      Wavoip::Calls::ConversationReopenService.perform!(conversation: conversation, status: :pending)

      expect(conversation.reload).to be_pending
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
    end

    it 'stamps agent when reopening as open (outbound call)' do
      Wavoip::Calls::ConversationReopenService.perform!(conversation: conversation, status: :open)

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['opened_by']).to eq('agent')
    end
  end

  describe 'Evolution pending cycle' do
    let(:channel) do
      create(
        :channel_whatsapp,
        account: account,
        provider: 'evolution',
        sync_templates: false,
        validate_provider_config: false,
        provider_config: Custom::Whatsapp::Evolution::ProviderConfig.build(
          'instance_name' => 'opened-by-instance',
          'api_key' => 'TEST-KEY',
          'conversation_pending' => true
        )
      )
    end
    let(:inbox) { channel.inbox.tap { |record| record.update!(lock_to_single_conversation: true) } }

    it 'keeps opened_by=contact when a resolved conversation reopens as pending' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :resolved,
        additional_attributes: { 'opened_by' => 'agent' }
      )

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)

      expect(conversation.reload).to be_pending
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
      expect(conversation.additional_attributes['evolution_pending_since']).to be_present
    end

    it 'keeps opened_by=contact when the second incoming message opens the pending cycle' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :pending,
        additional_attributes: {
          'opened_by' => 'contact',
          'evolution_pending_since' => 1.hour.ago.utc.iso8601(3)
        }
      )
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['opened_by']).to eq('contact')
      expect(conversation.additional_attributes['evolution_pending_since']).to be_blank
    end

    it 'keeps opened_by=phone when contact replies open a pending phone episode' do
      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        status: :pending,
        additional_attributes: {
          'opened_by' => 'phone',
          'evolution_pending_since' => 1.hour.ago.utc.iso8601(3)
        }
      )
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['opened_by']).to eq('phone')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
