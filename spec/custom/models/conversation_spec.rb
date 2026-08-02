require 'rails_helper'

RSpec.describe Conversation do
  describe 'unassigned too long dedup reset' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:agent) { create(:user, account: account) }
    let(:rule) do
      create_workflow_rule!(
        account: account,
        name: 'Unassigned',
        trigger_type: :unassigned_too_long
      )
    end
    let(:conversation) do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        assignee: nil,
        created_at: 2.hours.ago
      )
    end

    it 'clears executions when assignee changes so the rule can fire again' do
      ConversationWorkflowRuleExecution.record!(
        rule: rule,
        conversation: conversation,
        last_activity_epoch: conversation.created_at.to_i
      )
      expect(ConversationWorkflowRuleExecution.count).to eq(1)

      conversation.update!(assignee: agent)
      expect(ConversationWorkflowRuleExecution.count).to eq(0)

      ConversationWorkflowRuleExecution.record!(
        rule: rule,
        conversation: conversation,
        last_activity_epoch: conversation.created_at.to_i
      )
      expect(ConversationWorkflowRuleExecution.count).to eq(1)
    end
  end

  describe 'WhatsApp group auto-assignment guard' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, email: 'group-agent@example.com', account: account, auto_offline: false) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
    let(:group_jid) { '120363012345678901@g.us' }

    before do
      create(:inbox_member, inbox: inbox, user: agent)
      allow(Redis::Alfred).to receive(:rpoplpush).and_return(agent.id)
    end

    it 'does not auto-assign agents on WhatsApp group conversations' do
      contact = create(:contact, account: account, phone_number: nil, identifier: group_jid)
      contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: group_jid)

      conversation = create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        assignee: nil
      )

      expect(conversation.reload.assignee).to be_nil
    end

    it 'still auto-assigns agents on 1:1 conversations' do
      conversation = create(
        :conversation,
        account: account,
        contact: create(:contact, account: account),
        inbox: inbox,
        assignee: nil
      )

      expect(conversation.reload.assignee).to eq(agent)
    end
  end
end
