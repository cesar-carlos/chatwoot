class V2::Reports::ServiceSessions::AgentBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    open_counts = open_sessions_scope.group(:assignee_id).count
    closed_data = closed_sessions_scope.group(:user_id).pluck(
      :user_id,
      Arel.sql('COUNT(*)'),
      Arel.sql("AVG(reporting_events.#{metric_column})")
    )

    closed_by_user = closed_data.index_by(&:first)

    account.account_users.includes(:user).map do |account_user|
      user_id = account_user.user_id
      closed_row = closed_by_user[user_id] || [user_id, 0, nil]

      {
        id: user_id,
        name: account_user.user.name,
        open_sessions_count: open_counts[user_id] || 0,
        closed_sessions_count: closed_row[1] || 0,
        avg_session_duration: closed_row[2]&.to_f
      }
    end
  end
end
