# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::RecordHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    return if event.record_url.blank? || event.external_call_id.blank?

    call = Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: event.external_call_id)
    return schedule_retry if call.blank?

    attach_recording(call)
  end

  private

  def schedule_retry
    Wavoip::RetryRecordAttachmentJob.perform_later(
      inbox.id,
      event.external_call_id,
      event.record_url
    )
  end

  def attach_recording(call)
    meta = (call.meta || {}).dup
    return if meta['record_url'] == event.record_url

    call.update!(meta: meta.merge('record_url' => event.record_url))
    Wavoip::AttachRecordingJob.perform_later(call.id, event.record_url)
  end
end
