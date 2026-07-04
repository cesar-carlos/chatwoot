# frozen_string_literal: true

class Wavoip::RetryRecordAttachmentJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 5
  RETRY_DELAY = 5.seconds

  def perform(inbox_id, provider_call_id, record_url, attempt = 1)
    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.blank?
    return unless Wavoip::Calls::RecordingPolicy.recording_feature_enabled?(inbox: inbox)

    call = Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: provider_call_id)
    return handle_missing_call(inbox_id, provider_call_id, record_url, attempt) if call.blank?
    return handle_missing_message(call, inbox_id, provider_call_id, record_url, attempt) if call.message.blank?

    attach_recording(call, record_url)
  end

  private

  def handle_missing_call(inbox_id, provider_call_id, record_url, attempt)
    return log_retry_exhausted("inbox_id=#{inbox_id} call_id=#{provider_call_id}") if attempt >= MAX_ATTEMPTS

    retry_later(inbox_id, provider_call_id, record_url, attempt)
  end

  def handle_missing_message(call, inbox_id, provider_call_id, record_url, attempt)
    if attempt >= MAX_ATTEMPTS
      return log_retry_exhausted(
        "no message call_id=#{call.id} provider_call_id=#{provider_call_id}"
      )
    end

    retry_later(inbox_id, provider_call_id, record_url, attempt)
  end

  def attach_recording(call, record_url)
    persist_record_meta!(call, record_url)
    Wavoip::Calls::RecordingAttachmentService.new(call: call, record_url: record_url).perform
  end

  def persist_record_meta!(call, record_url)
    meta = (call.meta || {}).dup
    return if meta['record_url'] == record_url

    call.update!(meta: meta.merge('record_url' => record_url))
  end

  def retry_later(inbox_id, provider_call_id, record_url, attempt)
    self.class.set(wait: RETRY_DELAY).perform_later(
      inbox_id,
      provider_call_id,
      record_url,
      attempt + 1
    )
  end

  def log_retry_exhausted(detail)
    Rails.logger.warn("[WAVOIP] RECORD retry exhausted #{detail}")
  end
end
