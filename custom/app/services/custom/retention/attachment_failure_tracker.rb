class Custom::Retention::AttachmentFailureTracker
  pattr_initialize [:account!, :run_id!, :event_recorder!]

  def record_failure(attachment, error_message)
    failure = AttachmentRetentionFailure.find_or_initialize_by(attachment_id: attachment.id)
    failure.assign_attributes(
      account_id: account.id,
      failure_count: failure.failure_count.to_i + 1,
      last_error: error_message,
      last_failed_at: Time.current
    )
    failure.save!

    return false unless failure.failure_count >= Custom::Retention::Policy.max_failure_attempts

    event_recorder.call(attachment, 'skipped_quarantine', error_message: error_message)
    log_quarantined(attachment, failure.failure_count)
    true
  end

  def clear_failure(attachment_id)
    AttachmentRetentionFailure.where(attachment_id: attachment_id).delete_all
  end

  private

  def log_quarantined(attachment, failure_count)
    Rails.logger.info(
      {
        component: 'Custom::Retention::PurgeMessageAttachmentsService',
        event: 'attachment_quarantined',
        account_id: account.id,
        attachment_id: attachment.id,
        message_id: attachment.message_id,
        failure_count: failure_count,
        run_id: run_id
      }.to_json
    )
  end
end
