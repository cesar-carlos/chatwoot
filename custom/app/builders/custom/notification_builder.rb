# frozen_string_literal: true

module Custom::NotificationBuilder
  SUBSCRIPTION_GATED_TYPES = %w[conversation_creation voice_call_incoming].freeze

  def build_notification
    return if SUBSCRIPTION_GATED_TYPES.include?(notification_type) && !user_subscribed_to_notification?

    super
  end
end

NotificationBuilder.prepend_mod_with('NotificationBuilder')
