module V2::Reports::ServiceSessions::MetricsHelper
  OPEN_CYCLE_JOIN_SQL = <<~SQL.squish.freeze
    LEFT JOIN (
      SELECT conversation_id, MAX(event_end_time) AS latest_opened_at
      FROM reporting_events
      WHERE name = 'conversation_opened'
      GROUP BY conversation_id
    ) recent_open_events
      ON recent_open_events.conversation_id = conversations.id
  SQL
  OPEN_SESSION_AGE_SECONDS_SQL = 'EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ' \
                                 'COALESCE(recent_open_events.latest_opened_at, conversations.created_at)))'.freeze

  private

  def percentile_cont_for_scope(scope, order_expression, percentile: 0.95)
    scope.unscope(:order)
         .pick(Arel.sql("PERCENTILE_CONT(#{percentile}) WITHIN GROUP (ORDER BY #{order_expression})"))
  end

  def metric_percentile_for_scope(scope, percentile: 0.95)
    percentile_cont_for_scope(scope, "reporting_events.#{metric_column}", percentile: percentile)
  end

  def open_sessions_aging_stats
    scope = open_sessions_scope.joins(OPEN_CYCLE_JOIN_SQL)

    avg_age_seconds, p95_age_seconds, over_24h, over_72h, over_7d = scope.unscope(:order).pick(
      Arel.sql("AVG(#{OPEN_SESSION_AGE_SECONDS_SQL})"),
      Arel.sql("PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY #{OPEN_SESSION_AGE_SECONDS_SQL})"),
      Arel.sql("SUM(CASE WHEN #{OPEN_SESSION_AGE_SECONDS_SQL} > 86400 THEN 1 ELSE 0 END)"),
      Arel.sql("SUM(CASE WHEN #{OPEN_SESSION_AGE_SECONDS_SQL} > 259200 THEN 1 ELSE 0 END)"),
      Arel.sql("SUM(CASE WHEN #{OPEN_SESSION_AGE_SECONDS_SQL} > 604800 THEN 1 ELSE 0 END)")
    )

    {
      avg_age_seconds: avg_age_seconds,
      p95_age_seconds: p95_age_seconds,
      over_24h: over_24h.to_i,
      over_72h: over_72h.to_i,
      over_7d: over_7d.to_i
    }
  end
end
