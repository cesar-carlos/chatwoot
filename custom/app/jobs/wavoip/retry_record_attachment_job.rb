# frozen_string_literal: true

class Wavoip::RetryRecordAttachmentJob < ApplicationJob
  queue_as :low

  MAX_ATTEMPTS = 5
  BASE_RETRY_DELAY = 5.seconds
  RetryContext = Struct.new(:inbox_id, :provider_call_id, :record_url, :attempt, :record_status, keyword_init: true)

  def perform(inbox_id, provider_call_id, record_url, attempt = 1, record_status: nil)
    ctx = RetryContext.new(
      inbox_id: inbox_id,
      provider_call_id: provider_call_id,
      record_url: record_url,
      attempt: attempt,
      record_status: record_status
    )
    inbox = Inbox.find_by(id: ctx.inbox_id)
    return if inbox.blank?
    return unless Wavoip::Calls::RecordingPolicy.recording_feature_enabled?(inbox: inbox)

    call = Wavoip::Calls::CallLookup.find(inbox: inbox, provider_call_id: ctx.provider_call_id)
    return handle_missing_call(ctx) if call.blank?
    return handle_missing_message(call, ctx) if call.message.blank?

    attach_recording(call, ctx.record_url, ctx.record_status)
  end

  private

  def handle_missing_call(ctx)
    return log_retry_exhausted("inbox_id=#{ctx.inbox_id} call_id=#{ctx.provider_call_id}") if ctx.attempt >= MAX_ATTEMPTS

    retry_later(ctx)
  end

  def handle_missing_message(call, ctx)
    if ctx.attempt >= MAX_ATTEMPTS
      return log_retry_exhausted(
        "no message call_id=#{call.id} provider_call_id=#{ctx.provider_call_id}"
      )
    end

    retry_later(ctx)
  end

  def attach_recording(call, record_url, record_status)
    persist_record_meta!(call, record_url, record_status)
    Wavoip::Calls::RecordingAttachmentService.new(call: call, record_url: record_url).perform
  end

  def persist_record_meta!(call, record_url, record_status)
    call.with_lock do
      call.reload
      meta = (call.meta || {}).dup
      changes = {}
      changes['record_url'] = record_url if meta['record_url'] != record_url
      changes['record_status'] = record_status if record_status.present? && meta['record_status'] != record_status
      next if changes.blank?

      call.update!(meta: meta.merge(changes))
    end
  end

  def retry_later(ctx)
    self.class.set(wait: retry_delay(ctx.attempt)).perform_later(
      ctx.inbox_id,
      ctx.provider_call_id,
      ctx.record_url,
      ctx.attempt + 1,
      record_status: ctx.record_status
    )
  end

  def retry_delay(attempt)
    BASE_RETRY_DELAY * (2**(attempt - 1))
  end

  def log_retry_exhausted(detail)
    Rails.logger.warn("[WAVOIP] RECORD retry exhausted #{detail}")
  end
end
