module Custom::V2::Reports::BotMetricsBuilder
  def bot_resolutions_count
    return super unless account.inboxes.exists?(lock_to_single_conversation: true)

    cycle_aware_bot_resolutions_count
  end

  def bot_handoffs_count
    return super unless account.inboxes.exists?(lock_to_single_conversation: true)

    cycle_aware_bot_handoffs_count
  end

  private

  def cycle_aware_bot_resolutions_count
    single_history_inbox_ids = account.inboxes.where(lock_to_single_conversation: true).pluck(:id)
    base_scope = account.reporting_events
                        .joins(:conversation)
                        .where(account_id: account.id, name: :conversation_bot_resolved, created_at: range)
                        .where.not(conversation_id: bot_handoff_conversation_ids_subquery)

    cycle_aware_count = base_scope.where(conversations: { inbox_id: single_history_inbox_ids }).count
    legacy_count = base_scope.where.not(conversations: { inbox_id: single_history_inbox_ids })
                             .select(:conversation_id).distinct.count

    cycle_aware_count + legacy_count
  end

  def cycle_aware_bot_handoffs_count
    single_history_inbox_ids = account.inboxes.where(lock_to_single_conversation: true).pluck(:id)
    base_scope = account.reporting_events
                        .joins(:conversation)
                        .where(account_id: account.id, name: :conversation_bot_handoff, created_at: range)

    cycle_aware_count = base_scope.where(conversations: { inbox_id: single_history_inbox_ids }).count
    legacy_count = base_scope.where.not(conversations: { inbox_id: single_history_inbox_ids })
                             .select(:conversation_id).distinct.count

    cycle_aware_count + legacy_count
  end
end
