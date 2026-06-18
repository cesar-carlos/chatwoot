class V2::Reports::ServiceSessions::TeamBuilder < V2::Reports::ServiceSessions::BaseBuilder
  UNASSIGNED_TEAM_ID = 0

  def build
    open_counts = open_sessions_by_team
    closed_by_team = closed_sessions_by_team
    rows = account.teams.map { |team| build_team_row(team, open_counts, closed_by_team) }
    rows << build_unassigned_row(open_counts, closed_by_team) if unassigned_sessions?(open_counts, closed_by_team)
    rows
  end

  private

  def open_sessions_by_team
    open_sessions_scope.group(:team_id).count
  end

  def closed_sessions_by_team
    closed_sessions_scope
      .joins(:conversation)
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

  def build_unassigned_row(open_counts, closed_by_team)
    closed_row = closed_by_team[nil] || [nil, 0, nil]

    {
      id: UNASSIGNED_TEAM_ID,
      name: nil,
      open_sessions_count: open_counts[nil] || 0,
      closed_sessions_count: closed_row[1] || 0,
      avg_session_duration: closed_row[2]&.to_f
    }
  end

  def unassigned_sessions?(open_counts, closed_by_team)
    (open_counts[nil] || 0).positive? || (closed_by_team[nil]&.second || 0).positive?
  end
end
