# frozen_string_literal: true

class Wavoip::RetryRecordAttachmentJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 5
  RETRY_DELAY = 5.seconds

  def perform(inbox_id, provider_call_id, record_url, attempt = 1)
    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.blank?

    call = Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: provider_call_id)
    if call.blank?
      if attempt >= MAX_ATTEMPTS
        Rails.logger.warn(
          "[WAVOIP] RECORD retry exhausted inbox_id=#{inbox_id} call_id=#{provider_call_id}"
        )
      else
        retry_later(inbox_id, provider_call_id, record_url, attempt)
      end
      return
    end

    if call.message.blank?
      if attempt >= MAX_ATTEMPTS
        Rails.logger.warn(
          "[WAVOIP] RECORD retry exhausted (no message) call_id=#{call.id} provider_call_id=#{provider_call_id}"
        )
      else
        retry_later(inbox_id, provider_call_id, record_url, attempt)
      end
      return
    end

    persist_record_meta!(call, record_url)
    Wavoip::Calls::RecordingAttachmentService.new(call: call, record_url: record_url).perform
  end

  private

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
end
