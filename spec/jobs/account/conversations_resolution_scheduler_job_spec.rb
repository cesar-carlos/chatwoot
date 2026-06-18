require 'rails_helper'

RSpec.describe Account::ConversationsResolutionSchedulerJob do
  subject(:job) { described_class.perform_later }

  let!(:account) { create(:account) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .on_queue('scheduled_jobs')
  end

  it 'enqueues Conversations::ResolutionJob' do
    account.update(auto_resolve_after: 10 * 60 * 24)
    expect(Conversations::ResolutionJob).to receive(:perform_later).with(account: account).once
    described_class.perform_now
  end

  it 'skips migrated accounts' do
    account.update!(
      auto_resolve_after: 10 * 60 * 24,
      settings: { 'workflow_rules_migrated_at' => Time.current.iso8601 }
    )

    expect(Conversations::ResolutionJob).not_to receive(:perform_later)
    described_class.perform_now
  end
end
