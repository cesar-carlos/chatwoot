class V2::Reports::ServiceSessions::TeamBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    open_counts = open_sessions_by_team
    closed_by_team = closed_sessions_by_team
    account.teams.map { |team| build_team_row(team, open_counts, closed_by_team) }
  end

  private

  def open_sessions_by_team
    open_sessions_scope.where.not(team_id: nil).group(:team_id).count
  end

  def closed_sessions_by_team
    closed_sessions_scope
      .joins(:conversation)
      .where.not(conversations: { team_id: nil })
      .group('conversations.team_id')
      .pluck(
        'conversations.team_id',
        Arel.sql('COUNT(*)'),
        Arel.sql("AVG(reporting_events.#{metric_column})")
      )
      .index_by(&:first)
  end

  def build_team_row(team, open_counts, closed_by_team)
    closed_row = closed_by_team[team.id] || [team.id, 0, nil]

    {
      id: team.id,
      name: team.name,
      open_sessions_count: open_counts[team.id] || 0,
      closed_sessions_count: closed_row[1] || 0,
      avg_session_duration: closed_row[2]&.to_f
    }
  end
end
