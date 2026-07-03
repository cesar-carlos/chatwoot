require 'rails_helper'

RSpec.describe Custom::ConversationWorkflow::RuleExecutor do
  subject(:executor) { described_class.new(account: account, rule: rule) }

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
    ConversationWorkflowRule.create!(
      account: account,
      name: 'Resolve inactive',
      trigger_type: :conversation_inactivity,
      duration_minutes: 60,
      resolve_on_match: true,
      conditions: []
    )
  end

  it 'resolves conversation and records execution once' do
    executor.perform_for_conversation(conversation)

    expect(conversation.reload.status).to eq('resolved')
    expect(ConversationWorkflowRuleExecution.count).to eq(1)
  end

  it 'skips duplicate execution for same activity epoch' do
    executor.perform_for_conversation(conversation)
    executor.perform_for_conversation(conversation)

    expect(ConversationWorkflowRuleExecution.count).to eq(1)
  end

  it 'skips inactivity when last_activity_at is blank' do
    allow(conversation).to receive(:last_activity_at).and_return(nil)

    executor.perform_for_conversation(conversation)

    expect(conversation.reload.status).to eq('open')
    expect(ConversationWorkflowRuleExecution.count).to eq(0)
  end

  it 'sets Current.executed_by during resolve pipeline' do
    executed_by = nil
    allow(Custom::Conversations::ResolveService).to receive(:new).and_wrap_original do |method, **args|
      executed_by = Current.executed_by
      method.call(**args)
    end

    executor.perform_for_conversation(conversation)

    expect(executed_by).to eq(rule)
    expect(Current.executed_by).to be_nil
  end

  it 'releases dedup when resolve fails' do
    allow(Custom::Conversations::ResolveService).to receive(:new).and_raise(StandardError, 'resolve failed')

    expect do
      executor.perform_for_conversation(conversation)
    end.not_to change(ConversationWorkflowRuleExecution, :count)
  end
end
