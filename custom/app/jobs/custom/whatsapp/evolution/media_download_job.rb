# frozen_string_literal: true

class Custom::Whatsapp::Evolution::MediaDownloadJob < ApplicationJob
  queue_as :low

  MEDIA_LOCK_TTL = 5.minutes.to_i

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ArgumentError

  def perform(channel_id, message_id, attachment_payload, message_type)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    message = Message.find_by(id: message_id)
    return if channel.blank? || message.blank?
    return if message.attachments.exists?
    return unless acquire_media_lock!(message_id)

    Custom::Whatsapp::Evolution::MediaAttachmentService.new(
      channel: channel,
      message: message,
      attachment_payload: attachment_payload.with_indifferent_access,
      message_type: message_type
    ).perform
  end

  private

  def acquire_media_lock!(message_id)
    key = format(Redis::RedisKeys::EVOLUTION_MEDIA_DOWNLOAD_LOCK, message_id: message_id)
    ::Redis::Alfred.set(key, true, nx: true, ex: MEDIA_LOCK_TTL)
  end
end
