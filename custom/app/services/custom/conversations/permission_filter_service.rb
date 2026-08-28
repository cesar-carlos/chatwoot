module Custom::Conversations::PermissionFilterService
  private

  def filter_by_permissions(permissions)
    # FORK: custom role team permission normalization — union granted scopes
    return super if permissions.include?('conversation_manage')

    scopes = []
    if permissions.include?('conversation_unassigned_manage')
      scopes << filter_unassigned_and_mine
    elsif permissions.include?('conversation_team_unassigned_manage')
      scopes << filter_team_unassigned_and_mine
    end
    scopes << filter_participating_and_mine if permissions.include?('conversation_participating_manage')

    return Conversation.none if scopes.empty?

    union_conversation_scopes(scopes)
  end

  def filter_team_unassigned_and_mine
    user_team_ids = user.teams.where(account_id: account.id).pluck(:id)
    mine = accessible_conversations.assigned_to(user).unscope(:order)
    team_unassigned = accessible_conversations.unassigned.where(team_id: user_team_ids).unscope(:order)

    Conversation.from("(#{mine.to_sql} UNION #{team_unassigned.to_sql}) as conversations")
                .where(account_id: account.id)
  end
end
