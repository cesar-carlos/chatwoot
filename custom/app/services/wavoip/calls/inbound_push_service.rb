# frozen_string_literal: true

class Wavoip::Calls::InboundPushService
  pattr_initialize [:call!, :inbox!]

  def perform
    return unless call.incoming?
    return if conversation.blank?

    agents_for_notification.find_each do |agent|
      next if notification_recently_sent?(agent)

      NotificationBuilder.new(
        notification_type: 'voice_call_incoming',
        user: agent,
        account: inbox.account,
        primary_actor: conversation,
        secondary_actor: call.contact
      ).perform
    end
  end

  private

  def conversation
    @conversation ||= call.conversation
  end

  def agents_for_notification
    online = inbox.available_agents
    return online if online.exists?

    assignee = conversation.assignee
    return User.where(id: assignee.id) if assignee.present?

    user_ids = inbox.member_ids | inbox.account.administrators.ids
    User.where(id: user_ids)
  end

  def notification_recently_sent?(user)
    conversation.notifications
                .where(user: user, notification_type: Notification.notification_types[:voice_call_incoming])
                .exists?(['created_at > ?', 1.minute.ago])
  end
end
