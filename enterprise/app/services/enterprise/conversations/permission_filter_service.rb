module Enterprise::Conversations::PermissionFilterService
  def perform
    return filter_by_permissions(permissions) if user_has_custom_role?

    super
  end

  private

  def user_has_custom_role?
    user_role == 'agent' && account_user&.custom_role_id.present?
  end

  def permissions
    account_user&.permissions || []
  end

  def filter_by_permissions(permissions)
    # Permission-based filtering with hierarchy
    # conversation_manage > conversation_unassigned_manage > conversation_participating_manage
    # conversation_team_unassigned_manage is handled by Custom::Conversations::PermissionFilterService overlay
    # Union participating when present so the list matches ConversationPolicy#show?
    return accessible_conversations if permissions.include?('conversation_manage')

    scopes = []
    scopes << filter_unassigned_and_mine if permissions.include?('conversation_unassigned_manage')
    scopes << filter_participating_and_mine if permissions.include?('conversation_participating_manage')

    return Conversation.none if scopes.empty?

    union_conversation_scopes(scopes)
  end

  def union_conversation_scopes(scopes)
    return Conversation.none if scopes.blank?
    return scopes.first if scopes.one?

    ids = scopes.flat_map { |scope| scope.unscope(:order).pluck(:id) }.uniq
    return Conversation.none if ids.empty?

    conversations.where(id: ids)
  end

  def filter_participating_and_mine
    conversations = accessible_conversations
    participant_conversation_ids = ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)

    conversations
      .where(assignee_id: user.id)
      .or(conversations.where(id: participant_conversation_ids))
  end

  def filter_unassigned_and_mine
    conversations = accessible_conversations
    conversations.unassigned.or(conversations.assigned_to(user))
  end
end
