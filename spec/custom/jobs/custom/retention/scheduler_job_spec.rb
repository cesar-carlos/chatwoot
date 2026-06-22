require 'rails_helper'

RSpec.describe Custom::Retention::SchedulerJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { instance_double(Account, id: 101) }

  def scope_for(*accounts)
    list = accounts
    list.define_singleton_method(:find_each) do |**_kwargs, &block|
      each(&block)
    end
    list
  end

  before do
    clear_enqueued_jobs
    allow(Redis::Alfred).to receive(:set).and_return(true)
    allow(Custom::Retention::Policy).to receive(:attachment_ttl).and_return(90.days)
    allow(Custom::Retention::Policy).to receive(:distribution_groups).and_return(1)
  end

  it 'enqueues purge jobs for accounts with expired eligible attachments' do
    allow(Custom::Retention::Policy).to receive(:enabled?).and_return(true)
    job = described_class.new
    allow(job).to receive(:accounts_scope).and_return(scope_for(account))
    expect(job).to receive(:enqueue_account_job).with(account).and_return(true)

    job.perform

    expect(Custom::Retention::PurgeRetentionAuditEventsJob).to have_been_enqueued
  end

  it 'does not enqueue purge when no accounts are due' do
    allow(Custom::Retention::Policy).to receive(:enabled?).and_return(true)
    job = described_class.new
    allow(job).to receive(:accounts_scope).and_return(scope_for)
    expect(job).not_to receive(:enqueue_account_job)

    job.perform

    expect(Custom::Retention::PurgeRetentionAuditEventsJob).to have_been_enqueued
  end

  it 'does not enqueue when retention is disabled' do
    allow(Custom::Retention::Policy).to receive(:enabled?).and_return(false)

    expect do
      described_class.perform_now
    end.not_to have_enqueued_job(Custom::Retention::PurgeAccountAttachmentsJob)
  end

  it 'skips enqueue when account was already scheduled for the day' do
    allow(Custom::Retention::Policy).to receive(:enabled?).and_return(true)
    allow(Redis::Alfred).to receive(:set).and_return(false)
    job = described_class.new
    allow(job).to receive(:accounts_scope).and_return(scope_for(account))

    expect(job).to receive(:enqueue_account_job).with(account).and_return(false)

    job.perform
  end

  it 'distributes accounts across distribution groups' do
    allow(Custom::Retention::Policy).to receive(:enabled?).and_return(true)
    allow(Custom::Retention::Policy).to receive(:distribution_groups).and_return(7)
    job = described_class.new
    allow(job).to receive(:accounts_scope).and_return(scope_for(account))

    remainder = Date.current.yday % 7
    due_today = account.id % 7 == remainder

    if due_today
      expect(job).to receive(:enqueue_account_job).with(account).and_return(true)
    else
      expect(job).not_to receive(:enqueue_account_job)
    end

    job.perform
  end

  describe '#enqueue_account_job' do
    let(:account) { create(:account) }

    before do
      allow_any_instance_of(Inbox).to receive(:create_default_working_hours) # rubocop:disable RSpec/AnyInstance
    end

    it 'enqueues the purge job when redis lock is acquired' do
      job = described_class.new

      expect do
        job.send(:enqueue_account_job, account)
      end.to have_enqueued_job(Custom::Retention::PurgeAccountAttachmentsJob).with(account)
    end
  end
end
