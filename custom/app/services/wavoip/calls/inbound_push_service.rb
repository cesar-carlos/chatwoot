# frozen_string_literal: true

class Wavoip::Calls::InboundPushService
  pattr_initialize [:call!, :inbox!]

  def perform
    return unless eligible_for_push?

    agents = agents_for_notification.to_a
    return if agents.blank?

    notify_agents(agents, recently_notified_user_ids(agents.map(&:id)))
  end

  private

  def eligible_for_push?
    call.incoming? &&
      !Wavoip::Calls::ClaimGuard.claimed?(call) &&
      conversation.present?
  end

  def conversation
    @conversation ||= call.conversation
  end

  def agents_for_notification
    Wavoip::Calls::IncomingCallRecipients.new(
      inbox: inbox,
      conversation: conversation
    ).users
  end

  def notify_agents(agents, recently_notified_ids)
    agents.each do |agent|
      next if recently_notified_ids.include?(agent.id)

      NotificationBuilder.new(
        notification_type: 'voice_call_incoming',
        user: agent,
        account: inbox.account,
        primary_actor: conversation,
        secondary_actor: call.contact
      ).perform
    end
  end

  def recently_notified_user_ids(user_ids)
    conversation.notifications
                .where(
                  user_id: user_ids,
                  notification_type: Notification.notification_types[:voice_call_incoming]
                )
                .where('created_at > ?', 1.minute.ago)
                .pluck(:user_id)
                .to_set
  end
end
