module Custom::Notification::EmailNotificationService
  private

  def send_notification_email
    return super unless notification.team_conversation_assignment?

    AgentNotifications::ConversationNotificationsMailer.with(account: notification.account).team_conversation_assignment(
      notification.conversation, notification.user, notification
    ).deliver_later
  end

  def user_subscribed_to_notification?
    return super unless notification.team_conversation_assignment?

    Custom::Notification::DeliveryAccess.allowed?(notification) &&
      notification.user.notification_settings.find_by(account_id: notification.account_id)&.email_team_conversation_assignment?
  end
end
