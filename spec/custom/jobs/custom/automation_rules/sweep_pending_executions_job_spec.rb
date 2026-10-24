require 'rails_helper'

RSpec.describe Custom::AutomationRules::SweepPendingExecutionsJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  before { account.enable_features!('delayed_automations') }

  it 'enqueues a per-row job for due pending rows but not future ones' do
    due_row = create(:automation_rule_pending_execution, account: account, conversation: conversation, due_at: 1.minute.ago)
    future_row = create(:automation_rule_pending_execution, account: account, due_at: 1.hour.from_now)

    expect { job.perform }.to have_enqueued_job(AutomationRules::ProcessPendingExecutionJob).exactly(:once)
    expect(AutomationRules::ProcessPendingExecutionJob).to have_been_enqueued.with(due_row)
    expect(AutomationRules::ProcessPendingExecutionJob).not_to have_been_enqueued.with(future_row)
  end

  it 'does not purge terminal rows' do
    old_row = travel_to(31.days.ago) { create(:automation_rule_pending_execution, account: account, status: :executed) }

    job.perform

    expect(old_row.reload).to be_executed
  end
end
