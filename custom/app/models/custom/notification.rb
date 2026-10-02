# frozen_string_literal: true

module Custom::Notification
  def self.prepended(base)
    base.before_validation :capture_assignment_team, on: :create
  end

  def notification_action_labels
    I18n.with_locale(recipient_locale) { { open: I18n.t('notification_actions.open'), read: I18n.t('notification_actions.read') } }
  end

  def push_event_data
    payload = super.merge(user_id: user_id, action_labels: notification_action_labels)
    payload[:notification_title] = push_message_title if team_conversation_assignment?
    payload
  end

  def push_message_title
    if team_conversation_assignment?
      return I18n.t('notifications.notification_title.team_conversation_assignment',
                    display_id: conversation.display_id, team_name: conversation.team&.name, locale: recipient_locale)
    end
    return voice_call_incoming_title if voice_call_incoming?

    super
  end

  def push_message_body
    return message_body(conversation.messages.incoming.last || conversation.messages.outgoing.last) if team_conversation_assignment?
    return voice_call_incoming_body if voice_call_incoming?

    super
  end

  private

  def recipient_locale
    locale = user.ui_settings['locale'].presence || account.locale
    I18n.available_locales.map(&:to_s).include?(locale.to_s) ? locale : account.locale
  end

  def capture_assignment_team
    self.meta = (meta || {}).merge('assignment_team_id' => conversation.team_id) if team_conversation_assignment?
  end

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
