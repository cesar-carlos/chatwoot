class Custom::Retention::PurgeRetentionAuditEventsJob < ApplicationJob
  queue_as :housekeeping

  def perform
    cutoff = Custom::Retention::Policy.audit_retention_days.days.ago
    deleted_count = AttachmentRetentionEvent.where(created_at: ...cutoff).delete_all

    log_completed(deleted_count, cutoff)
  end

  private

  def log_completed(deleted_count, cutoff)
    Rails.logger.info(
      {
        component: 'Custom::Retention::PurgeRetentionAuditEventsJob',
        event: 'completed',
        deleted_count: deleted_count,
        cutoff: cutoff.iso8601,
        audit_retention_days: Custom::Retention::Policy.audit_retention_days
      }.to_json
    )
  end
end
