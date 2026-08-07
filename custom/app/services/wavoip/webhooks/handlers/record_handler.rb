# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::RecordHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    return unless record_event?

    call = find_call_or_schedule_retry
    return unless call

    handle_call_record(call)
  end

  private

  def record_event?
    event.record_url.present? && event.external_call_id.present? &&
      Wavoip::Calls::RecordingPolicy.recording_feature_enabled?(inbox: inbox)
  end

  def find_call_or_schedule_retry
    call = Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: event.external_call_id)
    schedule_retry if call.blank?
    call
  end

  def handle_call_record(call)
    current_policy = policy(call)
    return persist_record_meta!(call) if current_policy.persist_status_only?
    unless current_policy.attachable?
      schedule_retry_if_waiting_for_completion(call)
      return
    end

    attach_if_new(call)
  end

  # READY can arrive before ENDED→completed. Persist URL and retry until the
  # call is attachable, instead of silently dropping the webhook.
  def schedule_retry_if_waiting_for_completion(call)
    return if call.status == 'completed'
    return if Wavoip::Calls::RecordingPolicy::BLOCKED_STATUSES.include?(event.record_status.to_s.upcase)
    return if Wavoip::Calls::RecordingPolicy::PENDING_STATUSES.include?(event.record_status.to_s.upcase)

    persist_record_meta!(call, include_record_url: true)
    Rails.logger.info(
      "[WAVOIP] event=record_retry_waiting_completion call_id=#{call.id} inbox_id=#{inbox.id} " \
      "provider_call_id=#{event.external_call_id}"
    )
    schedule_retry
  end

  def attach_if_new(call)
    already_known = (call.meta || {})['record_url'] == event.record_url
    persist_record_meta!(call, include_record_url: true)
    enqueue_attachment(call) unless already_known
  end

  def schedule_retry
    lock_key = "wavoip:record_retry:#{inbox.id}:#{event.external_call_id}"
    acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: 2.minutes)
    return unless acquired

    Wavoip::RetryRecordAttachmentJob.perform_later(
      inbox.id,
      event.external_call_id,
      event.record_url,
      record_status: event.record_status
    )
  end

  def enqueue_attachment(call)
    Wavoip::AttachRecordingJob.perform_later(call.id, event.record_url)
  end

  def persist_record_meta!(call, include_record_url: false)
    call.with_lock do
      call.reload
      meta = (call.meta || {}).dup
      changes = {}

      changes['record_status'] = event.record_status if event.record_status.present? && meta['record_status'] != event.record_status

      changes['record_url'] = event.record_url if include_record_url && meta['record_url'] != event.record_url

      next if changes.blank?

      call.update!(meta: meta.merge(changes))
    end
  end

  def policy(call)
    Wavoip::Calls::RecordingPolicy.new(
      inbox: inbox,
      record_url: event.record_url,
      record_status: event.record_status,
      call: call
    )
  end
end
