class Custom::Notification::DeliveryAccess
  def self.allowed?(notification)
    account_user = AccountUser.find_by(user_id: notification.user_id, account_id: notification.account_id)
    return false unless account_user && notification.account.reload.active?

    conversation = notification.conversation
    return false unless conversation

    conversation.reload
    return false unless Custom::Notification::TeamAssignmentEligibility.allowed_notification?(notification)

    context = { user: notification.user, account: notification.account, account_user: account_user }
    NotificationPolicy.new(context, Notification).access? &&
      ConversationPolicy.new(context, conversation).show?
  rescue ActiveRecord::RecordNotFound
    false
  end
end
