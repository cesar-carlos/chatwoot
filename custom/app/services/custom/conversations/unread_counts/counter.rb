# rubocop:disable Metrics/ModuleLength -- participant-only unread union on exclusive assignment modes
module Custom::Conversations::UnreadCounts::Counter
  TEAM_UNASSIGNED_PERMISSION = 'conversation_team_unassigned_manage'.freeze
  PARTICIPATING_PERMISSION = Conversations::UnreadCounts::Counter::PARTICIPATING_PERMISSION
  MANAGE_ALL_PERMISSION = Conversations::UnreadCounts::Counter::MANAGE_ALL_PERMISSION

  private

  def unread_inbox_counts
    merge_positive_counts(super, participant_only_unread_inbox_counts)
  end

  def unread_label_counts
    base =
      if permission_mode == :team_unassigned_and_mine
        merge_positive_counts(team_mode_label_assignee_counts, team_mode_label_unassigned_counts)
      else
        super
      end

    merge_positive_counts(base, participant_only_unread_label_counts)
  end

  def unread_team_counts
    merge_positive_counts(super, participant_only_unread_team_counts)
  end

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
      permissions.exclude?(MANAGE_ALL_PERMISSION) &&
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

  def participating_union?
    custom_role_agent? &&
      permissions.include?(PARTICIPATING_PERMISSION) &&
      permissions.exclude?(MANAGE_ALL_PERMISSION)
  end

  def participant_only_unread_conversations
    return Conversation.none unless participating_union?

    @participant_only_unread_conversations ||= scoped_participant_only_unread
  end

  def scoped_participant_only_unread
    relation = participant_unread_base

    case permission_mode
    when :unassigned_and_mine
      relation.where.not(assignee_id: nil)
    when :team_unassigned_and_mine
      exclude_already_counted_team_unassigned(relation)
    when :mine
      relation
    else
      Conversation.none
    end
  end

  def participant_unread_base
    participant_ids = ConversationParticipant.where(account_id: account.id, user_id: user.id).select(:conversation_id)

    Conversations::PermissionFilterService.new(unread_open_conversations, user, account)
                                          .perform
                                          .where(id: participant_ids)
                                          .where.not(assignee_id: user.id)
  end

  def exclude_already_counted_team_unassigned(relation)
    team_ids = visible_team_ids
    return relation if team_ids.empty?

    relation.where(
      'conversations.assignee_id IS NOT NULL OR conversations.team_id IS NULL OR conversations.team_id NOT IN (?)',
      team_ids
    )
  end

  def unread_open_conversations
    conversations = Conversation.arel_table
    messages = Message.arel_table
    unread_since = conversations[:agent_last_seen_at].eq(nil).or(messages[:created_at].gt(conversations[:agent_last_seen_at]))

    account.conversations.open
           .joins(:messages)
           .merge(Message.incoming.reorder(nil))
           .where(messages: { account_id: account.id })
           .where(unread_since)
           .distinct
  end

  def participant_only_unread_inbox_counts
    participant_only_unread_conversations.unscope(:order).group(:inbox_id).count
  end

  def participant_only_unread_team_counts
    participant_only_unread_conversations.unscope(:order).where.not(team_id: nil).group(:team_id).count
  end

  def participant_only_unread_label_counts
    title_to_id = account.labels.where(id: sidebar_label_ids).pluck(:title, :id).to_h
    counts = Hash.new(0)

    participant_only_unread_conversations.find_each do |conversation|
      conversation.cached_label_list_array.each do |title|
        label_id = title_to_id[title]
        counts[label_id] += 1 if label_id
      end
    end

    counts
  end
end
# rubocop:enable Metrics/ModuleLength
