module Custom::ConversationPolicy
  private

  def manage_all_conversations?(permissions)
    # FORK: custom role team permission normalization
    permissions.include?('conversation_manage') && inbox_access?
  end

  def permits_unassigned_manage?(permissions)
    return false unless permissions.include?('conversation_unassigned_manage')
    return false unless inbox_access? # FORK: custom role team permission normalization

    unassigned_conversation? || assigned_to_user?
  end

  def permits_participating?(permissions)
    return false unless inbox_access? # FORK: custom role team permission normalization

    if permissions.include?('conversation_team_unassigned_manage')
      return assigned_to_user? || (unassigned_conversation? && conversation_belongs_to_user_team?)
    end

    return false unless permissions.include?('conversation_participating_manage')

    assigned_to_user? || participant?
  end

  def conversation_belongs_to_user_team?
    return false if record.team_id.blank?

    user.teams.where(account_id: record.account_id).exists?(id: record.team_id)
  end
end
