class V2::Reports::ServiceSessions::SummaryBuilder < V2::Reports::ServiceSessions::BaseBuilder
  def build
    open_count = open_sessions_scope.count
    closed_scope = closed_sessions_scope
    closed_count = closed_scope.count
    first_response_events = first_response_scope
    aging_stats = open_sessions_aging_stats

    {
      open_sessions_count: open_count,
      closed_sessions_count: closed_count,
      total_sessions: open_count + closed_count,
      **duration_metrics(closed_scope, first_response_events),
      **advanced_metrics(closed_count, closed_scope, first_response_events, aging_stats)
    }
  end

  private

  def duration_metrics(closed_scope, first_response_events)
    {
      avg_session_duration: closed_scope.average(metric_column)&.to_f,
      avg_first_response_time: first_response_events.average(metric_column)&.to_f
    }
  end

  def advanced_metrics(closed_count, closed_scope, first_response_events, aging_stats)
    {
      reopen_rate: reopen_rate(closed_count).round(4),
      p95_first_response_time: normalize_seconds(metric_percentile_for_scope(first_response_events)),
      p95_session_resolution_time: normalize_seconds(metric_percentile_for_scope(closed_scope)),
      open_sessions_avg_age_seconds: normalize_seconds(aging_stats[:avg_age_seconds]),
      open_sessions_p95_age_seconds: normalize_seconds(aging_stats[:p95_age_seconds]),
      open_sessions_aging_buckets: aging_bucket_payload(aging_stats)
    }
  end

  def reopen_rate(closed_count)
    return 0.0 if closed_count.zero?

    reopen_events_scope.count.to_f / closed_count
  end

  def aging_bucket_payload(aging_stats)
    {
      over_24h: aging_stats[:over_24h],
      over_72h: aging_stats[:over_72h],
      over_7d: aging_stats[:over_7d]
    }
  end

  def normalize_seconds(value)
    value&.round
  end
end
