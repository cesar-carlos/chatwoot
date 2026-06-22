class Custom::Retention::SchedulerJob < ApplicationJob
  queue_as :housekeeping

  SCHEDULED_KEY_FORMAT = 'RETENTION_SCHEDULED::%<account_id>s::%<date>s'.freeze
  SCHEDULED_KEY_TTL = 25.hours

  def perform
    return unless Custom::Retention::Policy.enabled?

    enqueue_due_accounts
    Custom::Retention::PurgeRetentionAuditEventsJob.perform_later
  end

  private

  def enqueue_due_accounts
    distribution_groups = Custom::Retention::Policy.distribution_groups
    accounts_enqueued = 0
    accounts_skipped = 0
    remainder = Date.current.yday % distribution_groups
    cutoff = Custom::Retention::Policy.attachment_ttl.ago

    accounts_scope(cutoff).find_each(batch_size: 100) do |account|
      next unless account.id % distribution_groups == remainder

      if enqueue_account_job(account)
        accounts_enqueued += 1
      else
        accounts_skipped += 1
      end
    end

    log_completed(accounts_enqueued, accounts_skipped, distribution_groups, remainder, cutoff)
  end

  def enqueue_account_job(account)
    schedule_key = format(SCHEDULED_KEY_FORMAT, account_id: account.id, date: Date.current.iso8601)
    return false unless Redis::Alfred.set(schedule_key, '1', nx: true, ex: SCHEDULED_KEY_TTL.to_i)

    Custom::Retention::PurgeAccountAttachmentsJob
      .set(wait: rand(1..30).minutes)
      .perform_later(account)

    true
  end

  def log_completed(accounts_enqueued, accounts_skipped, distribution_groups, remainder, cutoff)
    Rails.logger.info(
      {
        component: 'Custom::Retention::SchedulerJob',
        event: 'completed',
        accounts_enqueued: accounts_enqueued,
        accounts_skipped: accounts_skipped,
        distribution_groups: distribution_groups,
        remainder: remainder,
        cutoff: cutoff.iso8601
      }.to_json
    )
  end

  def accounts_scope(cutoff)
    Account.where(
      id: Custom::Retention::Policy
        .expirable_attachments_scope(cutoff: cutoff)
        .select(:account_id)
        .distinct
    )
  end
end
