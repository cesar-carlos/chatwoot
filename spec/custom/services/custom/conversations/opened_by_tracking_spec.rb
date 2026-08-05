# frozen_string_literal: true

require 'rails_helper'

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
end
