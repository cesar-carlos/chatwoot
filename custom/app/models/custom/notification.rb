# frozen_string_literal: true

module Custom::Notification
  def push_message_title
    return voice_call_incoming_title if voice_call_incoming?

    super
  end

  def push_message_body
    return voice_call_incoming_body if voice_call_incoming?

    super
  end

  private

  def voice_call_incoming?
    notification_type == 'voice_call_incoming'
  end

  def voice_call_incoming_title
    I18n.t(
      'notifications.notification_title.voice_call_incoming',
      display_id: conversation.display_id,
      inbox_name: primary_actor.inbox.name
    )
  end

  def voice_call_incoming_body
    contact = secondary_actor
    contact_name = contact&.name.presence || contact&.phone_number
    return I18n.t('notifications.voice_call_incoming_body', contact_name: contact_name) if contact_name.present?

    I18n.t('notifications.voice_call_incoming_body_unknown')
  end
end
