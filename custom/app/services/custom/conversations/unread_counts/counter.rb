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

  def unread_label_counts
    return super unless permission_mode == :team_unassigned_and_mine

    merge_positive_counts(team_mode_label_assignee_counts, team_mode_label_unassigned_counts)
  end

  def team_mode_label_assignee_counts
    keys_by_id = Hash.new { |hash, key| hash[key] = [] }
    sidebar_label_ids.each do |label_id|
      visible_inbox_ids.each do |inbox_id|
        keys_by_id[label_id] << store.label_inbox_assignee_key(account.id, label_id, inbox_id, user.id)
      end
    end

    counts_for_grouped_keys(keys_by_id)
  end

  def team_mode_label_unassigned_counts
    counts = Hash.new(0)

    sidebar_label_ids.each do |label_id|
      visible_inbox_ids.each do |inbox_id|
        label_key = store.label_inbox_unassigned_key(account.id, label_id, inbox_id)
        visible_team_ids.each do |team_id|
          team_key = store.team_inbox_unassigned_key(account.id, team_id, inbox_id)
          counts[label_id.to_s] += sinter_cardinality(label_key, team_key)
        end
      end
    end

    counts.reject { |_, count| count.zero? }
  end

  def sinter_cardinality(*keys)
    Redis::Alfred.with { |conn| conn.sinter(*keys).size }
  end

  def merge_positive_counts(*count_hashes)
    merged = Hash.new(0)
    count_hashes.each do |counts|
      counts.each { |id, count| merged[id.to_s] += count.to_i }
    end
    merged.reject { |_, count| count.zero? }
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
