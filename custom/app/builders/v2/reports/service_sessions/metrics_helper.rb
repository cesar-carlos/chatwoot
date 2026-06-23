module V2::Reports::ServiceSessions::MetricsHelper
  # FORK: align with Custom::Conversations::ResolutionCycle — cycle start only when lock is ON.
  OPEN_SESSION_STARTED_AT_SQL = <<~SQL.squish.freeze
    CASE
      WHEN inboxes.lock_to_single_conversation
        THEN COALESCE(recent_open_events.latest_opened_at, conversations.created_at)
      ELSE conversations.created_at
    END
  SQL
  OPEN_SESSION_AGE_SECONDS_SQL = "EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - #{OPEN_SESSION_STARTED_AT_SQL}))".freeze

  private

  def open_session_started_at_sql
    OPEN_SESSION_STARTED_AT_SQL
  end

  def percentile_cont_for_scope(scope, order_expression, percentile: 0.95)
    scope.unscope(:order)
         .pick(Arel.sql("PERCENTILE_CONT(#{percentile}) WITHIN GROUP (ORDER BY #{order_expression})"))
  end

  def metric_percentile_for_scope(scope, percentile: 0.95)
    percentile_cont_for_scope(scope, "reporting_events.#{metric_column}", percentile: percentile)
  end

  def open_sessions_aging_stats
    scope = open_sessions_snapshot_scope

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

  def open_cycle_join_sql
    sanitized_account_id = ActiveRecord::Base.connection.quote(account.id)
    join_sql = <<~SQL.squish
      LEFT JOIN (
        SELECT conversation_id, MAX(event_end_time) AS latest_opened_at
        FROM reporting_events
        WHERE name = 'conversation_opened'
          AND account_id = #{sanitized_account_id}
        GROUP BY conversation_id
      ) recent_open_events
        ON recent_open_events.conversation_id = conversations.id
    SQL

    Arel.sql(join_sql)
  end
end
