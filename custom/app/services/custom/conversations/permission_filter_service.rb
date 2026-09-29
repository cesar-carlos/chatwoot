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

    scopes.reduce { |combined_scope, scope| combined_scope.or(scope) }
  end

  def filter_team_unassigned_and_mine
    user_team_ids = user.teams.where(account_id: account.id).pluck(:id)
    conversations = accessible_conversations
    mine = conversations.assigned_to(user)
    team_unassigned = conversations.unassigned.where(team_id: user_team_ids)

    mine.or(team_unassigned)
  end
end
