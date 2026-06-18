require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::ActionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, waiting_since: 1.hour.ago) }
  let(:rule) do
    ConversationWorkflowRule.create!(
      account: account,
      name: 'Actions',
      trigger_type: :agent_no_reply,
      duration_minutes: 60,
      actions: [
        {
          'action_name' => 'send_message',
          'action_params' => ['Hello from workflow'],
          'counts_as_agent_reply' => true
        }
      ]
    )
  end

  it 'sends message with workflow metadata and clears waiting_since' do
    described_class.new(rule, account, conversation).perform

    message = conversation.messages.where(private: false).last
    expect(message.content).to eq('Hello from workflow')
    expect(message.content_attributes['conversation_workflow_rule_id']).to eq(rule.id)
    expect(message.content_attributes['counts_as_agent_reply']).to be(true)
    expect(conversation.reload.waiting_since).to be_nil
  end

  it 'does not reset Current.executed_by' do
    Current.executed_by = rule
    described_class.new(rule, account, conversation).perform
    expect(Current.executed_by).to eq(rule)
    Current.reset
  end
end
