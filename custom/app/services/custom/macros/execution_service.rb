# frozen_string_literal: true

module Custom::Macros::ExecutionService
  VOICE_ONLY_SKIP_LOG = '[Macros] Skipped action on voice-only inbox'

  def send_message(message)
    super
  rescue CustomExceptions::Wavoip::VoiceOnlyInbox => e
    Rails.logger.info("#{VOICE_ONLY_SKIP_LOG}: send_message — #{e.message}")
  end

  def send_attachment(blob_ids)
    super
  rescue CustomExceptions::Wavoip::VoiceOnlyInbox => e
    Rails.logger.info("#{VOICE_ONLY_SKIP_LOG}: send_attachment — #{e.message}")
  end
end
