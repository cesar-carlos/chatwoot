require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::PreviewCountService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account) }

  before { account.enable_features!(:conversation_agent_no_reply_rules) }

  it 'excludes conversations that fail conditions' do
    matching = create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 2.hours.ago,
      assignee: agent
    )
    create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 2.hours.ago,
      assignee_id: nil
    )

    count = described_class.new(
      account: account,
      attributes: {
        trigger_type: 'agent_no_reply',
        duration_minutes: 60,
        conditions: [
          {
            'attribute_key' => 'assignee_id',
            'filter_operator' => 'equal_to',
            'values' => [agent.id],
            'query_operator' => 'AND'
          }
        ]
      }
    ).perform

    expect(count).to eq(1)
    expect(matching.assignee_id).to eq(agent.id)
  end
end

RSpec.describe Custom::ConversationWorkflow::RuleExecutor do
  describe 'pipeline failure rollback' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        status: :open,
        last_activity_at: 2.hours.ago,
        waiting_since: nil
      )
    end
    let(:rule) do
      create_workflow_rule!(
        account: account,
        name: 'Resolve inactive',
        trigger_type: :conversation_inactivity,
        resolve_on_match: true
      )
    end

    it 'releases dedup when resolve fails' do
      allow(Custom::Conversations::ResolveService).to receive(:new).and_raise(StandardError, 'resolve failed')

      expect do
        described_class.new(account: account, rule: rule).perform_for_conversation(conversation)
      end.not_to change(ConversationWorkflowRuleExecution, :count)
    end
  end
end

RSpec.describe 'Unassigned too long dedup reset' do
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

RSpec.describe Custom::Message::WorkflowRulesScheduler do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:rule) do
    create_workflow_rule!(
      account: account,
      name: 'Customer no reply',
      trigger_type: :customer_no_reply,
      active: true
    )
  end

  before do
    account.enable_features!(:auto_resolve_conversations)
    allow(Custom::ConversationWorkflow::ScheduleOnMessageJob).to receive(:set).and_return(
      Custom::ConversationWorkflow::ScheduleOnMessageJob
    )
    allow(Custom::ConversationWorkflow::ScheduleOnMessageJob).to receive(:perform_later)
  end

  it 'does not schedule customer_no_reply for workflow-generated outgoing messages' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content: 'Workflow nudge',
      content_attributes: { conversation_workflow_rule_id: rule.id }
    )

    expect(Custom::ConversationWorkflow::ScheduleOnMessageJob).not_to have_received(:perform_later)
  end
end
