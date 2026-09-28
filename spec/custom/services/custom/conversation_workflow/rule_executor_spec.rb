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

  it 'executes a rule when its conditions match' do
    agent = create(:user, account: account)
    conversation.update!(assignee: agent)
    rule.update!(
      conditions: [
        {
          'attribute_key' => 'assignee_id',
          'filter_operator' => 'equal_to',
          'values' => [agent.id],
          'query_operator' => 'AND'
        }
      ]
    )

    executor.perform_for_conversation(conversation)

    expect(conversation.reload).to be_resolved
  end

  it 'evaluates business-hour rules as soon as their wall-clock prefilter is reached' do
    inbox.update!(working_hours_enabled: true, timezone: 'UTC')
    inbox.working_hours.delete_all
    7.times do |day_of_week|
      create(
        :working_hour,
        inbox: inbox,
        day_of_week: day_of_week,
        open_all_day: true,
        closed_all_day: false
      )
    end
    conversation.update!(last_activity_at: 70.minutes.ago)
    rule.update!(options: { 'respect_business_hours' => true })

    executor.perform

    expect(conversation.reload).to be_resolved
  end

  it 'continues past already claimed candidates on later scheduler runs' do
    stub_const('Limits::BULK_ACTIONS_LIMIT', 2)
    bulk_rule = ConversationWorkflowRule.create!(
      account: account,
      name: 'Label inactive',
      trigger_type: :conversation_inactivity,
      duration_minutes: 60,
      actions: [{ 'action_name' => 'add_label', 'action_params' => ['reviewed'] }]
    )
    3.times do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        status: :open,
        last_activity_at: 2.hours.ago,
        waiting_since: nil
      )
    end
    bulk_executor = described_class.new(account: account, rule: bulk_rule)

    bulk_executor.perform
    expect(bulk_rule.conversation_workflow_rule_executions.count).to eq(2)

    bulk_executor.perform
    expect(bulk_rule.conversation_workflow_rule_executions.count).to eq(3)
  end
end
