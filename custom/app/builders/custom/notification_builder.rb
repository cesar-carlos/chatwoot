# frozen_string_literal: true

module Custom::NotificationBuilder
  SUBSCRIPTION_GATED_TYPES = %w[conversation_creation voice_call_incoming team_conversation_assignment].freeze

  def build_notification
    return if notification_type == 'team_conversation_assignment' && !eligible_team_assignment?
    return if SUBSCRIPTION_GATED_TYPES.include?(notification_type) && !user_subscribed_to_notification?

    super
  end

  private

  def eligible_team_assignment?
    account_user = AccountUser.find_by(account_id: account.id, user_id: user.id)
    context = { user: user, account: account, account_user: account_user }
    account.active? && account_user.present? && NotificationPolicy.new(context, Notification).access? &&
      Custom::Notification::TeamAssignmentEligibility.allowed?(primary_actor, user, primary_actor.team_id)
  end

  def user_subscribed_to_notification?
    return super unless %w[conversation_creation team_conversation_assignment].include?(notification_type)

    settings = user.ui_settings || {}
    by_account = settings['popup_notification_flags_by_account']
    flags = by_account ? by_account[account.id.to_s] : settings['popup_notification_flags']
    return true if flags.is_a?(Array) && flags.include?("popup_#{notification_type}")

    super
  end
end
