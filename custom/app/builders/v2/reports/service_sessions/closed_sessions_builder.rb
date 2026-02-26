class V2::Reports::ServiceSessions::ClosedSessionsBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    ordered_scope = closed_sessions_scope
                    .includes(conversation: [:contact, :assignee, :inbox, :team])
                    .order(event_end_time: :desc)
    total_count = ordered_scope.count
    sessions = paginate_scope(ordered_scope)

    {
      sessions: sessions.map { |event| format_closed_session(event) },
      **pagination_meta(total_count)
    }
  end

  private

  def format_closed_session(event)
    conversation = event.conversation

    {
      id: event.id,
      conversation_id: conversation.id,
      display_id: conversation.display_id,
      contact: serialize_resource(conversation.contact),
      assignee: serialize_resource(conversation.assignee),
      inbox: serialize_resource(conversation.inbox),
      team: serialize_resource(conversation.team),
      session_duration: event.value,
      session_duration_business_hours: event.value_in_business_hours,
      resolved_at: event.event_end_time&.to_i,
      session_started_at: event.event_start_time&.to_i
    }
  end

  def serialize_resource(resource)
    return nil if resource.blank?

    {
      id: resource.id,
      name: resource.try(:name) || resource.try(:title)
    }
  end
end
