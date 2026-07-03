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
end
