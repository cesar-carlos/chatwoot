class Custom::Notification::AccessibleScope
  SCOPED_CONVERSATION_PERMISSIONS = %w[
    conversation_unassigned_manage conversation_team_unassigned_manage conversation_participating_manage
  ].freeze

  def self.for(user:, account:)
    new(user, account).notifications
  end

  def initialize(user, account)
    @user = user
    @account = account
    @account_user = AccountUser.find_by(user: user, account: account)
  end

  def notifications
    scope = @user.notifications.where(account_id: @account.id)
    context = { user: @user, account: @account, account_user: @account_user }
    return scope.none unless @account_user && @account.reload.active? && NotificationPolicy.new(context, Notification).access?

    scope.where(primary_actor_type: 'Conversation', primary_actor_id: conversations.select(:id))
  end

  private

  # Keep the SQL scope aligned with ConversationPolicy#show? (including Custom roles).
  def conversations
    scope = @account.conversations
    return scope if @account_user.administrator? && @account_user.custom_role_id.blank?

    inbox_scope = scope.where(inbox_id: @user.inboxes.where(account_id: @account.id).select(:id))
    team_scope = scope.where(team_id: @user.teams.where(account_id: @account.id).select(:id))
    return inbox_scope.or(team_scope) if @account_user.custom_role_id.blank?

    permitted_conversations(inbox_scope)
  end

  def permitted_conversations(scope)
    permissions = @account_user.custom_role&.permissions || []
    return scope if permissions.include?('conversation_manage')
    return scope.none unless permissions.intersect?(SCOPED_CONVERSATION_PERMISSIONS)

    result = scope.where(assignee_id: @user.id)
    alternatives = unassigned_conversations(scope, permissions)
    if permissions.include?('conversation_participating_manage')
      alternatives = alternatives.or(scope.where(id: ConversationParticipant.where(user_id: @user.id).select(:conversation_id)))
    end

    result.or(alternatives)
  end

  def unassigned_conversations(scope, permissions)
    if permissions.include?('conversation_unassigned_manage')
      scope.where(assignee_id: nil, assignee_agent_bot_id: nil)
    elsif permissions.include?('conversation_team_unassigned_manage')
      scope.where(assignee_id: nil, assignee_agent_bot_id: nil,
                  team_id: @user.teams.where(account_id: @account.id).select(:id))
    else
      scope.none
    end
  end
end
