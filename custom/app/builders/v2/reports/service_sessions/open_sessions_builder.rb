class V2::Reports::ServiceSessions::OpenSessionsBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    base_scope = open_sessions_scope
    total_count = base_scope.count
    cycle_started_sql = open_session_started_at_sql
    ordered_scope = base_scope
                    .select("conversations.*, (#{cycle_started_sql}) AS cycle_started_at_sql")
                    .includes(:contact, :assignee, :inbox, :team)
                    .order(Arel.sql("#{cycle_started_sql} DESC"))
    sessions = paginate_scope(ordered_scope)

    {
      sessions: sessions.map { |conversation| format_open_session(conversation) },
      **pagination_meta(total_count)
    }
  end

  private

  def format_open_session(conversation)
    cycle_started_at = conversation.read_attribute('cycle_started_at_sql') || conversation.created_at

    {
      id: conversation.id,
      display_id: conversation.display_id,
      contact: serialize_resource(conversation.contact),
      assignee: serialize_resource(conversation.assignee),
      inbox: serialize_resource(conversation.inbox),
      team: serialize_resource(conversation.team),
      session_started_at: cycle_started_at.to_i,
      status: conversation.status,
      waiting_since: conversation.waiting_since&.to_i
    }
  end
end
