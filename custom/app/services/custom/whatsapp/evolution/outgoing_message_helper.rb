# frozen_string_literal: true

# Shared helpers for building outgoing Evolution messages from Baileys payloads.
# Included by PhoneOutgoingSyncService and Import::MessagesImporter.
module Custom::Whatsapp::Evolution::OutgoingMessageHelper
  OUTGOING_MEDIA_TYPES = %w[image video audio document sticker].freeze

  def outgoing_media_message?(message_data)
    return false if message_data.blank?

    data = message_data.with_indifferent_access
    type = data[:type].to_s
    OUTGOING_MEDIA_TYPES.include?(type) && data[type].present?
  end

  def media_caption(message_data)
    data = message_data.with_indifferent_access
    type = data[:type].to_s
    return unless OUTGOING_MEDIA_TYPES.include?(type)

    data[type]&.dig(:caption) || data[type]&.dig('caption')
  end

  def extract_fallback_text(record)
    message = record['message'] || {}
    message['conversation'] || message.dig('extendedTextMessage', 'text')
  end

  def outgoing_content(record, message_data)
    return extract_fallback_text(record) if message_data.blank?

    message_data.dig(:text, :body) || media_caption(message_data) || extract_fallback_text(record)
  end

  def message_timestamp(value)
    seconds = value.to_i
    return Time.zone.at(seconds) if seconds.positive?

    Time.current
  end

  def enqueue_outgoing_media_download!(message, message_data)
    return unless outgoing_media_message?(message_data)

    data = message_data.with_indifferent_access
    type = data[:type].to_s
    attachment_payload = data[type]
    return if attachment_payload.blank?

    Custom::Whatsapp::Evolution::MediaDownloadJob.perform_later(
      channel.id,
      message.id,
      attachment_payload.deep_stringify_keys,
      type
    )
  end
end
