class Custom::Retention::PurgeMessageAttachmentsService
  BATCH_SIZE = 500
  PURGED_IDS_LOG_LIMIT = 100

  pattr_initialize [:account!, :run_id]

  def perform
    ttl = Custom::Retention::Policy.attachment_ttl
    return empty_result unless ttl

    purge_before_cutoff(ttl.ago)
  end

  private

  def run_id
    @run_id ||= SecureRandom.uuid
  end

  def failure_tracker
    @failure_tracker ||= Custom::Retention::AttachmentFailureTracker.new(
      account: account,
      run_id: run_id,
      event_recorder: method(:record_purge_event)
    )
  end

  def empty_result
    result(0, false, 0, 0)
  end

  def purge_before_cutoff(cutoff)
    stats = initial_stats
    max_per_run = Custom::Retention::Policy.max_purge_per_run

    log_event(
      'start',
      account_id: account.id,
      cutoff: cutoff.iso8601,
      max_per_run: max_per_run,
      dry_run: dry_run?,
      run_id: run_id
    )

    expired_attachments(cutoff).limit(max_per_run).find_in_batches(batch_size: BATCH_SIZE) do |batch|
      merge_stats!(stats, purge_batch(batch))
    end

    has_more = compute_has_more(cutoff)
    log_completion(cutoff: cutoff, has_more: has_more, stats: stats)

    result(stats[:deleted_count], has_more, stats[:failed_count], stats[:bytes_freed])
  end

  def compute_has_more(cutoff)
    return false if dry_run?

    expired_attachments(cutoff).exists?
  end

  def initial_stats
    { deleted_count: 0, failed_count: 0, bytes_freed: 0, purged_attachment_ids: [] }
  end

  def merge_stats!(stats, batch_stats)
    stats[:deleted_count] += batch_stats[:deleted_count]
    stats[:failed_count] += batch_stats[:failed_count]
    stats[:bytes_freed] += batch_stats[:bytes_freed]
    stats[:purged_attachment_ids].concat(batch_stats[:purged_attachment_ids])
  end

  def purge_batch(batch)
    batch.each_with_object(deleted_count: 0, failed_count: 0, bytes_freed: 0, purged_attachment_ids: []) do |attachment, stats|
      purge_result = purge_attachment(attachment)
      if purge_result[:success]
        stats[:deleted_count] += 1
        stats[:bytes_freed] += purge_result[:bytes_freed]
        stats[:purged_attachment_ids] << attachment.id
      else
        stats[:failed_count] += 1
      end
    end
  end

  def log_completion(cutoff:, has_more:, stats:)
    purged_attachment_ids = stats[:purged_attachment_ids]
    log_event(
      'completed',
      account_id: account.id,
      cutoff: cutoff.iso8601,
      deleted_count: stats[:deleted_count],
      failed_count: stats[:failed_count],
      bytes_freed: stats[:bytes_freed],
      has_more: has_more,
      dry_run: dry_run?,
      run_id: run_id,
      purged_attachment_ids: purged_attachment_ids.first(PURGED_IDS_LOG_LIMIT),
      purged_attachment_ids_truncated: purged_attachment_ids.size > PURGED_IDS_LOG_LIMIT
    )
  end

  def result(deleted_count, has_more, failed_count, bytes_freed)
    {
      deleted_count: deleted_count,
      has_more: has_more,
      failed_count: failed_count,
      bytes_freed: bytes_freed
    }
  end

  def expired_attachments(cutoff)
    Custom::Retention::Policy.expirable_attachments_scope(cutoff: cutoff, account_id: account.id)
  end

  def purge_attachment(attachment)
    metadata = attachment_metadata(attachment)
    message = attachment.message

    return dry_run_purge(attachment, metadata) if dry_run?

    live_purge(attachment, message, metadata)
  rescue StandardError => e
    handle_purge_failure(attachment, e, metadata)
  end

  def attachment_metadata(attachment)
    {
      bytes_freed: attachment.file.blob&.byte_size.to_i,
      blob_key: attachment.file.blob&.key
    }
  end

  def dry_run_purge(attachment, metadata)
    record_purge_event(attachment, 'dry_run', byte_size: metadata[:bytes_freed], blob_key: metadata[:blob_key])
    { success: true, bytes_freed: metadata[:bytes_freed] }
  end

  def live_purge(attachment, message, metadata)
    attachment.destroy!
    failure_tracker.clear_failure(attachment.id)
    record_purge_event(attachment, 'purged', byte_size: metadata[:bytes_freed], blob_key: metadata[:blob_key])
    Custom::Retention::MessagePostPurgeService.new(message: message, account: account, run_id: run_id).perform
    { success: true, bytes_freed: metadata[:bytes_freed] }
  end

  def handle_purge_failure(attachment, error, metadata)
    quarantined = failure_tracker.record_failure(attachment, error.message)
    record_failed_purge_event(attachment, error, metadata) unless quarantined
    log_purge_failure(attachment, error, quarantined)
    { success: false, bytes_freed: 0 }
  end

  def record_failed_purge_event(attachment, error, metadata)
    record_purge_event(
      attachment,
      'failed',
      error_message: error.message,
      byte_size: metadata[:bytes_freed],
      blob_key: metadata[:blob_key]
    )
  end

  def log_purge_failure(attachment, error, quarantined)
    log_event(
      'purge_failed',
      account_id: account.id,
      attachment_id: attachment.id,
      message_id: attachment.message_id,
      error: error.message,
      quarantined: quarantined,
      run_id: run_id
    )
  end

  def record_purge_event(attachment, status, error_message: nil, byte_size: nil, blob_key: nil)
    Custom::Retention::RecordPurgeEventService.new(
      account: account,
      attachment: attachment,
      run_id: run_id,
      status: status,
      error_message: error_message,
      byte_size: byte_size,
      blob_key: blob_key
    ).perform
  rescue StandardError => e
    log_event(
      'audit_record_failed',
      account_id: account.id,
      attachment_id: attachment.id,
      status: status,
      error: e.message,
      run_id: run_id
    )
  end

  def dry_run?
    Custom::Retention::Policy.dry_run?
  end

  def log_event(event, payload)
    Rails.logger.info(
      {
        component: 'Custom::Retention::PurgeMessageAttachmentsService',
        event: event,
        **payload
      }.to_json
    )
  end
end
