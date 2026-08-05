# frozen_string_literal: true

module Custom::AutomationRules::ActionService
  VOICE_ONLY_SKIP_LOG = '[AutomationRules] Skipped action on voice-only inbox'

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

  # FORK: interpolate Liquid in team email body before mailer (template prints custom_message raw)
  def send_email_to_team(params)
    payload = params[0]
    return super if payload.blank?

    message = Custom::Liquid::MessageContentRenderer.render(
      payload[:message] || payload['message'],
      conversation: @conversation,
      executed_by: @rule
    )
    interpolated = payload.merge(message: message).with_indifferent_access
    super([interpolated])
  end
end
