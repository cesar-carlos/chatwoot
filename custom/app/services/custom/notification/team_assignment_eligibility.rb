class Custom::Notification::TeamAssignmentEligibility
  def self.allowed_notification?(notification)
    return true unless notification.team_conversation_assignment?

    allowed?(notification.conversation, notification.user, notification.meta&.fetch('assignment_team_id', nil))
  end

  def self.allowed?(conversation, user, team_id)
    return false unless conversation.open? && team_id.present? && conversation.team_id == team_id
    return false if conversation.assignee_id.present? || conversation.assignee_agent_bot_id.present? || conversation.ai_assignee_type.present?

    user.teams.where(account_id: conversation.account_id).exists?(id: team_id)
  end
end
