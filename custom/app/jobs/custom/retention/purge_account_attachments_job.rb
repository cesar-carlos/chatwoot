class Custom::Retention::PurgeAccountAttachmentsJob < MutexApplicationJob
  queue_as :purgable

  LOCK_KEY_FORMAT = 'RETENTION_PURGE_MUTEX::%<account_id>s'.freeze
  LOCK_TIMEOUT = 30.minutes

  discard_on ActiveRecord::RecordNotFound

  retry_on_lock_conflict wait: 1.minute, attempts: 3, on_exhaustion: :log_and_discard

  def perform(account, attempt = 0)
    return unless Custom::Retention::Policy.enabled?

    account = account.is_a?(Account) ? account : Account.find(account)
    lock_key = format(LOCK_KEY_FORMAT, account_id: account.id)

    with_lock(lock_key, LOCK_TIMEOUT) do
      execute_purge(account, attempt)
    end
  end

  def log_and_discard(account, attempt = 0)
    account_id = account.is_a?(Account) ? account.id : account
    Rails.logger.warn(
      {
        component: 'Custom::Retention::PurgeAccountAttachmentsJob',
        event: 'lock_skipped',
        account_id: account_id,
        attempt: attempt
      }.to_json
    )
  end

  private

  def execute_purge(account, attempt)
    run_id = SecureRandom.uuid
    purge_result = Custom::Retention::PurgeMessageAttachmentsService.new(account: account, run_id: run_id).perform

    return unless purge_result[:has_more]

    next_attempt = attempt + 1
    if next_attempt >= Custom::Retention::Policy.max_reenqueue_attempts
      Custom::Retention::OperationalAlert.reenqueue_limit_reached(
        account_id: account.id,
        attempt: next_attempt,
        purge_result: purge_result
      )
      return
    end

    self.class.set(wait: 1.minute).perform_later(account, next_attempt)
  end
end
