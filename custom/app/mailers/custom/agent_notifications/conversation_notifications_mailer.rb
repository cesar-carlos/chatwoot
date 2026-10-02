module Custom::AgentNotifications::ConversationNotificationsMailer
  def self.prepended(base)
    base.append_view_path Rails.root.join('custom/app/views/mailers')
  end

  def team_conversation_assignment(conversation, agent, notification)
    return unless smtp_config_set_or_development?
    return if notification.read_at.present?
    return unless Custom::Notification::DeliveryAccess.allowed?(notification)
    return unless agent.notification_settings.find_by(account_id: conversation.account_id)&.email_team_conversation_assignment?

    @agent = agent
    @conversation = conversation
    @action_url = app_account_conversation_url(account_id: conversation.account_id, id: conversation.display_id)
    @assignment_title = I18n.t('notifications.notification_title.team_conversation_assignment',
                               display_id: conversation.display_id, team_name: notification.assignment_team_name)
    mail(to: agent.email, subject: @assignment_title) { |format| format.html { render } }
  end

  private

  def liquid_locals
    super.merge(team_assignment_title: @assignment_title)
  end
end
