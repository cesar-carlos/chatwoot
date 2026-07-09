# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::MediaDownloadJob < ApplicationJob
  # :default (not :low) so attachments don't lag behind lower-priority background
  # work such as contact enrichment or imports; agents are waiting on this.
  queue_as :default

  MEDIA_LOCK_TTL = 5.minutes.to_i

  retry_on StandardError, wait: :polynomially_longer, attempts: 5
  discard_on ArgumentError

  def perform(channel_id, message_id, attachment_payload, message_type)
    @media_lock_acquired = false
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution_go')
    return if channel.blank?

    message = Message.find_by(id: message_id)
    # Retry when the inbound transaction has not committed yet (enqueue race).
    raise ActiveRecord::RecordNotFound, "Evolution Go media message_id=#{message_id} not found" if message.blank?
    return if message.attachments.exists?

    acquire_media_lock!(message_id)

    Custom::Whatsapp::EvolutionGo::MediaAttachmentService.new(
      channel: channel,
      message: message,
      attachment_payload: attachment_payload.with_indifferent_access,
      message_type: message_type
    ).perform
  ensure
    release_media_lock!(message_id) if message_id.present? && @media_lock_acquired
  end

  private

  def acquire_media_lock!(message_id)
    @media_lock_acquired = ::Redis::Alfred.set(media_lock_key(message_id), true, nx: true, ex: MEDIA_LOCK_TTL)
    return if @media_lock_acquired

    raise MutexApplicationJob::LockAcquisitionError,
          "Evolution Go media download lock busy for message_id=#{message_id}"
  end

  def release_media_lock!(message_id)
    ::Redis::Alfred.delete(media_lock_key(message_id))
    @media_lock_acquired = false
  end

  def media_lock_key(message_id)
    format(Redis::RedisKeys::EVOLUTION_GO_MEDIA_DOWNLOAD_LOCK, message_id: message_id)
  end
end
