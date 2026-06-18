class V2::Reports::ServiceSessions::OpenSessionsBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    ordered_scope = open_sessions_scope
                    .includes(:contact, :assignee, :inbox, :team)
                    .order(last_activity_at: :desc, created_at: :desc)
    total_count = ordered_scope.count
    sessions = paginate_scope(ordered_scope)
    cycle_started_at_by_conversation_id = latest_cycle_start_time_for(sessions.pluck(:id))

    {
      sessions: sessions.map do |conversation|
        format_open_session(conversation, cycle_started_at_by_conversation_id[conversation.id])
      end,
      **pagination_meta(total_count)
    }
  end

  private

  def format_open_session(conversation, cycle_started_at)
    {
      id: conversation.id,
      display_id: conversation.display_id,
      contact: serialize_resource(conversation.contact),
      assignee: serialize_resource(conversation.assignee),
      inbox: serialize_resource(conversation.inbox),
      team: serialize_resource(conversation.team),
      # FORK: expose session start (cycle start), not last activity timestamp.
      session_started_at: (cycle_started_at || conversation.created_at)&.to_i,
      status: conversation.status,
      waiting_since: conversation.waiting_since&.to_i
    }
  end

  def latest_cycle_start_time_for(conversation_ids)
    return {} if conversation_ids.blank?

    account.reporting_events
           .where(conversation_id: conversation_ids, name: 'conversation_opened')
           .group(:conversation_id)
           .maximum(:event_end_time)
  end
end
