module Custom::Conversations::UnreadCounts::Counter
  TEAM_UNASSIGNED_PERMISSION = 'conversation_team_unassigned_manage'.freeze

  private

  def permission_mode
    @permission_mode ||=
      if team_unassigned_permission?
        :team_unassigned_and_mine
      else
        super
      end
  end

  def team_unassigned_permission?
    custom_role_agent? &&
      permissions.exclude?(Conversations::UnreadCounts::Counter::MANAGE_ALL_PERMISSION) &&
      permissions.exclude?(Conversations::UnreadCounts::Counter::UNASSIGNED_PERMISSION) &&
      permissions.include?(TEAM_UNASSIGNED_PERMISSION)
  end

  def assignment_mode?
    return true if permission_mode == :team_unassigned_and_mine

    super
  end

  def inbox_keys_for_mode(inbox_id)
    if permission_mode == :team_unassigned_and_mine
      visible_team_ids.map { |team_id| store.team_inbox_unassigned_key(account.id, team_id, inbox_id) } +
        [store.inbox_assignee_key(account.id, inbox_id, user.id)]
    else
      super
    end
  end

  def label_inbox_keys_for_mode(label_id, inbox_id)
    if permission_mode == :team_unassigned_and_mine
      # Store has no label+team+unassigned composite key; assignee keys only avoid
      # over-counting unassigned conversations from other teams via label_inbox_unassigned.
      [store.label_inbox_assignee_key(account.id, label_id, inbox_id, user.id)]
    else
      super
    end
  end

  def team_inbox_keys_for_mode(team_id, inbox_id)
    if permission_mode == :team_unassigned_and_mine
      [
        store.team_inbox_unassigned_key(account.id, team_id, inbox_id),
        store.team_inbox_assignee_key(account.id, team_id, inbox_id, user.id)
      ]
    else
      super
    end
  end
end
