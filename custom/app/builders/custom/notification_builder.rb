# frozen_string_literal: true

module Custom::NotificationBuilder
  SUBSCRIPTION_GATED_TYPES = %w[conversation_creation voice_call_incoming].freeze

  def build_notification
    return if SUBSCRIPTION_GATED_TYPES.include?(notification_type) && !user_subscribed_to_notification?

    super
  end

  private

  def user_subscribed_to_notification?
    return super unless notification_type == 'conversation_creation'

    settings = user.ui_settings || {}
    by_account = settings['popup_notification_flags_by_account']
    flags = by_account ? by_account[account.id.to_s] : settings['popup_notification_flags']
    return true if flags.is_a?(Array) && flags.include?('popup_conversation_creation')

    super
  end
end
