module Custom::Conversations::PermissionFilterService
  private

  def filter_by_permissions(permissions)
    # FORK: custom role team permission normalization
    return super if permissions.include?('conversation_manage')
    return super if permissions.include?('conversation_unassigned_manage')
    return filter_team_unassigned_and_mine if permissions.include?('conversation_team_unassigned_manage')

    super
  end

  def filter_team_unassigned_and_mine
    user_team_ids = user.teams.where(account_id: account.id).pluck(:id)
    mine = accessible_conversations.assigned_to(user)
    team_unassigned = accessible_conversations.unassigned.where(team_id: user_team_ids)

    Conversation.from("(#{mine.to_sql} UNION #{team_unassigned.to_sql}) as conversations")
                .where(account_id: account.id)
  end
end
