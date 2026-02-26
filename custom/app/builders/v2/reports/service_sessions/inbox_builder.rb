class V2::Reports::ServiceSessions::InboxBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    open_counts = open_sessions_scope.group(:inbox_id).count
    closed_data = closed_sessions_scope.group(:inbox_id).pluck(
      :inbox_id,
      Arel.sql('COUNT(*)'),
      Arel.sql("AVG(reporting_events.#{metric_column})")
    )

    closed_by_inbox = closed_data.index_by(&:first)

    account.inboxes.map do |inbox|
      closed_row = closed_by_inbox[inbox.id] || [inbox.id, 0, nil]

      {
        id: inbox.id,
        name: inbox.name,
        open_sessions_count: open_counts[inbox.id] || 0,
        closed_sessions_count: closed_row[1] || 0,
        avg_session_duration: closed_row[2]&.to_f
      }
    end
  end
end
