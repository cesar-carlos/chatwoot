# frozen_string_literal: true

class Wavoip::Calls::RecordingAttachmentService
  DEFAULT_FILENAME_EXTENSION = 'ogg'
  ALLOWED_CONTENT_TYPE_PREFIXES = %w[audio/].freeze

  pattr_initialize [:call!, :record_url!, :store_fallback_on_error]

  def perform
    return if record_url.blank?
    return if call.message.blank?
    return unless recording_allowed?
    return if already_attached?

    SafeFetch.fetch(
      record_url,
      allowed_content_type_prefixes: ALLOWED_CONTENT_TYPE_PREFIXES
    ) do |result|
      persist_recording!(result)
    end
  rescue SafeFetch::Error => e
    Rails.logger.warn("[WAVOIP] recording fetch failed call_id=#{call.id} error=#{e.class}")
    # The direct-URL fallback (no webhook) retries on failure — recordings can
    # take a few minutes to become available, so don't lock in an unplayable
    # URL before we know the download actually succeeded.
    store_external_url_fallback! unless store_fallback_on_error == false
  end

  private

  def persist_recording!(result)
    call.with_lock do
      next if already_attached?

      call.recording.attach(
        io: result.tempfile,
        filename: recording_filename(result),
        content_type: recording_content_type(result)
      )
      sync_message_recording_url!
      call.message.touch # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def store_external_url_fallback!
    meta = (call.meta || {}).dup
    return if meta['record_url'] == record_url

    call.update!(meta: meta.merge('record_url' => record_url))
    sync_message_recording_url!(record_url)
  end

  def sync_message_recording_url!(url = nil)
    message = call.message
    return unless message

    url ||= call.recording_url
    return if url.blank?

    message.update!(
      content_attributes: (message.content_attributes || {}).deep_merge(
        'data' => { 'recording_url' => url }
      )
    )
  end

  def already_attached?
    call.recording.attached?
  end

  def recording_filename(result)
    result.original_filename.presence || "wavoip-call-#{call.provider_call_id}.#{DEFAULT_FILENAME_EXTENSION}"
  end

  def recording_content_type(result)
    result.content_type.presence || 'audio/ogg'
  end

  def recording_allowed?
    Wavoip::Calls::RecordingPolicy.attachable?(
      inbox: call.inbox,
      record_url: record_url,
      record_status: call.meta&.dig('record_status'),
      call: call
    )
  end
end
