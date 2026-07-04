# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::RecordHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    return if event.record_url.blank? || event.external_call_id.blank?
    return unless Wavoip::Calls::RecordingPolicy.recording_feature_enabled?(inbox: inbox)

    call = Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: event.external_call_id)
    return schedule_retry if call.blank?

    current_policy = policy(call)
    if current_policy.persist_status_only?
      persist_record_meta!(call)
      return
    end
    return unless current_policy.attachable?

    persist_record_meta!(call, include_record_url: true)
    enqueue_attachment(call)
  end

  private

  def schedule_retry
    Wavoip::RetryRecordAttachmentJob.perform_later(
      inbox.id,
      event.external_call_id,
      event.record_url
    )
  end

  def enqueue_attachment(call)
    return if (call.meta || {})['record_url'] == event.record_url

    Wavoip::AttachRecordingJob.perform_later(call.id, event.record_url)
  end

  def persist_record_meta!(call, include_record_url: false)
    meta = (call.meta || {}).dup
    changes = {}

    if event.record_status.present? && meta['record_status'] != event.record_status
      changes['record_status'] = event.record_status
    end

    if include_record_url && meta['record_url'] != event.record_url
      changes['record_url'] = event.record_url
    end

    return if changes.blank?

    call.update!(meta: meta.merge(changes))
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
