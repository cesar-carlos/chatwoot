# frozen_string_literal: true

module Custom::Macros::ExecutionService
  VOICE_ONLY_SKIP_LOG = '[Macros] Skipped action on voice-only inbox'

  def perform
    Current.executed_by = @macro
    super
  end

  def send_message(message)
    super
  rescue Pundit::NotAuthorizedError => e
    # FORK: custom role reply assigned only
    Rails.logger.info("[Macros] Skipped send_message — not authorized to reply: #{e.message}")
  rescue CustomExceptions::Wavoip::VoiceOnlyInbox => e
    Rails.logger.info("#{VOICE_ONLY_SKIP_LOG}: send_message — #{e.message}")
  end

  def send_attachment(blob_ids)
    super
  rescue Pundit::NotAuthorizedError => e
    # FORK: custom role reply assigned only
    Rails.logger.info("[Macros] Skipped send_attachment — not authorized to reply: #{e.message}")
  rescue CustomExceptions::Wavoip::VoiceOnlyInbox => e
    Rails.logger.info("#{VOICE_ONLY_SKIP_LOG}: send_attachment — #{e.message}")
  end

  def add_private_note(message)
    super
  rescue Pundit::NotAuthorizedError => e
    # FORK: custom role reply assigned only
    Rails.logger.info("[Macros] Skipped add_private_note — not authorized to reply: #{e.message}")
  end
end
