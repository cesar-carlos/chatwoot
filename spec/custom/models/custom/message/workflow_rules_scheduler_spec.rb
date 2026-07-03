require 'rails_helper'

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
