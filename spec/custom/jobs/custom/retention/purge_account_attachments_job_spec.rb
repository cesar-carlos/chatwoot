require 'rails_helper'

RSpec.describe Custom::Retention::PurgeAccountAttachmentsJob, type: :job do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:lock_manager) { instance_double(Redis::LockManager) }

  before do
    clear_enqueued_jobs
    clear_performed_jobs
    allow(Redis::LockManager).to receive(:new).and_return(lock_manager)
    allow(lock_manager).to receive(:lock).and_return(true)
    allow(lock_manager).to receive(:unlock).and_return(true)
  end

  it 'stops re-enqueueing after the configured attempt limit' do
    service = instance_double(Custom::Retention::PurgeMessageAttachmentsService)
    allow(Custom::Retention::PurgeMessageAttachmentsService).to receive(:new).and_return(service)
    allow(service).to receive(:perform).and_return(
      deleted_count: 1,
      has_more: true,
      failed_count: 0,
      bytes_freed: 10
    )

    with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                      MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                      MESSAGE_ATTACHMENT_RETENTION_MAX_REENQUEUE_ATTEMPTS: '2' do
      GlobalConfig.clear_cache

      described_class.perform_now(account, 2)

      expect(described_class).not_to have_been_enqueued
    end
  end

  it 're-enqueues when backlog remains and attempts are below the limit' do
    service = instance_double(Custom::Retention::PurgeMessageAttachmentsService)
    allow(Custom::Retention::PurgeMessageAttachmentsService).to receive(:new).and_return(service)
    allow(service).to receive(:perform).and_return(
      deleted_count: 1,
      has_more: true,
      failed_count: 0,
      bytes_freed: 10
    )

    with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                      MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                      MESSAGE_ATTACHMENT_RETENTION_MAX_REENQUEUE_ATTEMPTS: '5' do
      GlobalConfig.clear_cache

      expect do
        described_class.perform_now(account, 0)
      end.to have_enqueued_job(described_class).with(account, 1)
    end
  end

  it 'alerts when reenqueue limit is reached' do
    service = instance_double(Custom::Retention::PurgeMessageAttachmentsService)
    purge_result = { deleted_count: 1, has_more: true, failed_count: 0, bytes_freed: 10 }
    allow(Custom::Retention::PurgeMessageAttachmentsService).to receive(:new).and_return(service)
    allow(service).to receive(:perform).and_return(purge_result)

    with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                      MESSAGE_ATTACHMENT_RETENTION_DAYS: '90',
                      MESSAGE_ATTACHMENT_RETENTION_MAX_REENQUEUE_ATTEMPTS: '1' do
      GlobalConfig.clear_cache

      expect(Custom::Retention::OperationalAlert).to receive(:reenqueue_limit_reached).with(
        account_id: account.id,
        attempt: 1,
        purge_result: purge_result
      )

      described_class.perform_now(account, 0)
    end
  end

  it 'logs lock_skipped via log_and_discard' do
    job = described_class.new

    expect(Rails.logger).to receive(:warn).with(a_string_including('lock_skipped', account.id.to_s))

    job.log_and_discard(account, 0)
  end

  it 'does not purge when lock cannot be acquired after retries' do
    allow(lock_manager).to receive(:lock).and_return(false)

    with_modified_env MESSAGE_ATTACHMENT_RETENTION_ENABLED: 'true',
                      MESSAGE_ATTACHMENT_RETENTION_DAYS: '90' do
      GlobalConfig.clear_cache

      expect(Custom::Retention::PurgeMessageAttachmentsService).not_to receive(:new)

      described_class.perform_now(account, 0)
    end
  end
end
