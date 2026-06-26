require 'rails_helper'

# rubocop:disable RSpec/MultipleDescribes -- job and scheduler specs share setup patterns
RSpec.describe Custom::ConversationWorkflow::ScheduleOnMessageJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 30.minutes.ago
    )
  end
  let(:rule) do
    create_workflow_rule!(
      account: account,
      name: 'Agent no reply',
      trigger_type: :agent_no_reply,
      active: true
    )
  end

  before do
    account.enable_features!(:conversation_agent_no_reply_rules)
    allow(Custom::ConversationWorkflow::RuleExecutor).to receive(:new).and_return(
      instance_double(Custom::ConversationWorkflow::RuleExecutor, perform_for_conversation: true)
    )
  end

  it 'runs the executor for a specific conversation' do
    executor = instance_double(Custom::ConversationWorkflow::RuleExecutor, perform_for_conversation: true)
    allow(Custom::ConversationWorkflow::RuleExecutor).to receive(:new).and_return(executor)

    described_class.perform_now(rule_id: rule.id, conversation_id: conversation.id)

    expect(Custom::ConversationWorkflow::RuleExecutor).to have_received(:new).with(
      account: account,
      rule: rule
    )
    expect(executor).to have_received(:perform_for_conversation).with(conversation)
  end

  it 'clears the redis schedule slot after running' do
    epoch = conversation.waiting_since.to_i
    key = "#{Custom::ConversationWorkflow::ScheduleOnMessageScheduler::REDIS_KEY_PREFIX}:#{rule.id}:#{conversation.id}:#{epoch}"
    Redis::Alfred.set(key, Time.current.to_i)

    described_class.perform_now(rule_id: rule.id, conversation_id: conversation.id, reference_epoch: epoch)

    expect(Redis::Alfred.exists?(key)).to be(false)
  end

  it 'skips inactive rules' do
    rule.update!(active: false)
    executor = instance_double(Custom::ConversationWorkflow::RuleExecutor, perform_for_conversation: true)
    allow(Custom::ConversationWorkflow::RuleExecutor).to receive(:new).and_return(executor)

    described_class.perform_now(rule_id: rule.id, conversation_id: conversation.id)

    expect(executor).not_to have_received(:perform_for_conversation)
  end
end

RSpec.describe Custom::ConversationWorkflow::ScheduleOnMessageScheduler do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      status: :open,
      waiting_since: 50.minutes.ago
    )
  end
  let(:rule) do
    create_workflow_rule!(
      account: account,
      name: 'Agent no reply',
      trigger_type: :agent_no_reply,
      active: true
    )
  end

  before do
    allow(Custom::ConversationWorkflow::ScheduleOnMessageJob).to receive(:set).and_return(
      Custom::ConversationWorkflow::ScheduleOnMessageJob
    )
    allow(Custom::ConversationWorkflow::ScheduleOnMessageJob).to receive(:perform_later)
  end

  after do
    epoch = conversation.waiting_since&.to_i
    Redis::Alfred.delete(
      "#{Custom::ConversationWorkflow::ScheduleOnMessageScheduler::REDIS_KEY_PREFIX}:#{rule.id}:#{conversation.id}:#{epoch}"
    )
  end

  it 'schedules remaining wait time from waiting_since' do
    freeze_time do
      # rubocop:disable Rails/SkipsModelValidations -- precise timestamp for scheduler math
      conversation.update_column(:waiting_since, 50.minutes.ago)
      # rubocop:enable Rails/SkipsModelValidations
      conversation.reload
      epoch = conversation.waiting_since.to_i

      described_class.new(rule: rule, conversation: conversation).perform

      expect(Custom::ConversationWorkflow::ScheduleOnMessageJob).to have_received(:set).with(
        wait: 600.seconds
      )
      expect(Custom::ConversationWorkflow::ScheduleOnMessageJob).to have_received(:perform_later).with(
        conversation_id: conversation.id,
        rule_id: rule.id,
        reference_epoch: epoch
      )
    end
  end

  it 'does not schedule duplicate jobs while redis slot is claimed' do
    freeze_time do
      # rubocop:disable Rails/SkipsModelValidations -- precise timestamp for scheduler math
      conversation.update_column(:waiting_since, 50.minutes.ago)
      # rubocop:enable Rails/SkipsModelValidations
      conversation.reload

      described_class.new(rule: rule, conversation: conversation).perform
      described_class.new(rule: rule, conversation: conversation).perform

      expect(Custom::ConversationWorkflow::ScheduleOnMessageJob).to have_received(:perform_later).once
    end
  end

  it 'does not schedule when respect_business_hours is enabled' do
    rule.update!(options: { 'respect_business_hours' => true })

    described_class.new(rule: rule, conversation: conversation).perform

    expect(Custom::ConversationWorkflow::ScheduleOnMessageJob).not_to have_received(:perform_later)
  end
end
# rubocop:enable RSpec/MultipleDescribes
