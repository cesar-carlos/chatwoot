module Custom::ConversationPolicy
  def show?
    return false unless administrator? || agent_bot? || agent_can_view_conversation?
    return true unless custom_role_permissions?

    permissions = custom_role_permissions
    return true if manage_all_conversations?(permissions)
    return true if permits_unassigned_manage?(permissions)
    return true if permits_team_unassigned_manage?(permissions)

    permits_participating?(permissions)
  end

  private

  def manage_all_conversations?(permissions)
    permissions.include?('conversation_manage') && inbox_access?
  end

  def permits_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_unassigned_manage')
    return false unless inbox_access?

    unassigned_conversation? || assigned_to_user?
  end

  def permits_team_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_team_unassigned_manage')
    return false unless inbox_access?

    assigned_to_user? || (unassigned_conversation? && conversation_belongs_to_user_team?)
  end

  def permits_participating?(permissions)
    return false unless inbox_access?
    return false unless permissions.include?('conversation_participating_manage')

    assigned_to_user? || participant?
  end

  def conversation_belongs_to_user_team?
    return false if record.team_id.blank?

    user.teams.where(account_id: record.account_id).exists?(id: record.team_id)
  end

  def unassigned_conversation?
    record.assignee_id.nil?
  end

  def custom_role_permissions?
    account_user&.custom_role_id.present?
  end

  def custom_role_permissions
    account_user&.custom_role&.permissions || []
  end
end
