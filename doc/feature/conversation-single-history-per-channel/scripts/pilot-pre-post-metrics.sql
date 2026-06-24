-- Single-history pilot: pre/post comparison metrics (one result set per inbox)
-- Parameters (psql \set): account_id, pilot_inbox_ids_csv, pre_start_at, pre_end_at, post_start_at, post_end_at

WITH params AS (
  SELECT
    :account_id::bigint AS account_id,
    :pre_start_at::timestamp AS pre_start_at,
    :pre_end_at::timestamp AS pre_end_at,
    :post_start_at::timestamp AS post_start_at,
    :post_end_at::timestamp AS post_end_at
),
windows AS (
  SELECT 'pre' AS period, pre_start_at AS start_at, pre_end_at AS end_at FROM params
  UNION ALL
  SELECT 'post' AS period, post_start_at AS start_at, post_end_at AS end_at FROM params
),
pilot_inboxes AS (
  SELECT unnest(string_to_array(:pilot_inbox_ids_csv, ','))::bigint AS inbox_id
),
conversation_created AS (
  SELECT
    w.period,
    c.inbox_id,
    COUNT(*) AS conversations_created
  FROM windows w
  JOIN conversations c
    ON c.created_at >= w.start_at
   AND c.created_at < w.end_at
  JOIN params p ON p.account_id = c.account_id
  JOIN pilot_inboxes pi ON pi.inbox_id = c.inbox_id
  GROUP BY w.period, c.inbox_id
),
event_counts AS (
  SELECT
    w.period,
    re.inbox_id,
    COUNT(*) FILTER (WHERE re.name = 'conversation_opened') AS conversation_opened_count,
    COUNT(*) FILTER (WHERE re.name = 'conversation_resolved') AS conversation_resolved_count
  FROM windows w
  JOIN reporting_events re
    ON re.created_at >= w.start_at
   AND re.created_at < w.end_at
  JOIN params p ON p.account_id = re.account_id
  JOIN pilot_inboxes pi ON pi.inbox_id = re.inbox_id
  WHERE re.name IN ('conversation_opened', 'conversation_resolved')
  GROUP BY w.period, re.inbox_id
),
latency AS (
  SELECT
    w.period,
    re.inbox_id,
    AVG(re.value) FILTER (WHERE re.name = 'conversation_resolved') AS avg_resolution_seconds,
    AVG(re.value) FILTER (WHERE re.name = 'first_response') AS avg_first_response_seconds,
    AVG(re.value) FILTER (WHERE re.name = 'reply_time') AS avg_reply_seconds,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY re.value)
      FILTER (WHERE re.name = 'conversation_resolved') AS p90_resolution_seconds,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY re.value)
      FILTER (WHERE re.name = 'reply_time') AS p90_reply_seconds
  FROM windows w
  JOIN reporting_events re
    ON re.created_at >= w.start_at
   AND re.created_at < w.end_at
  JOIN params p ON p.account_id = re.account_id
  JOIN pilot_inboxes pi ON pi.inbox_id = re.inbox_id
  WHERE re.name IN ('conversation_resolved', 'first_response', 'reply_time')
  GROUP BY w.period, re.inbox_id
),
duplicates AS (
  SELECT
    w.period,
    c.inbox_id,
    COUNT(*) AS duplicate_contact_inbox_days
  FROM windows w
  JOIN (
    SELECT
      c.inbox_id,
      c.contact_inbox_id,
      DATE_TRUNC('day', c.created_at) AS day_bucket,
      c.created_at,
      c.account_id
    FROM conversations c
  ) c
    ON c.created_at >= w.start_at
   AND c.created_at < w.end_at
  JOIN params p ON p.account_id = c.account_id
  JOIN pilot_inboxes pi ON pi.inbox_id = c.inbox_id
  GROUP BY w.period, c.inbox_id, c.contact_inbox_id, c.day_bucket
  HAVING COUNT(*) > 1
),
duplicates_summary AS (
  SELECT period, inbox_id, COUNT(*) AS duplicate_contact_inbox_days
  FROM duplicates
  GROUP BY period, inbox_id
)
SELECT
  coalesce(cc.period, ec.period, l.period, ds.period) AS period,
  coalesce(cc.inbox_id, ec.inbox_id, l.inbox_id, ds.inbox_id) AS inbox_id,
  coalesce(cc.conversations_created, 0) AS conversations_created,
  coalesce(ec.conversation_opened_count, 0) AS conversation_opened_count,
  coalesce(ec.conversation_resolved_count, 0) AS conversation_resolved_count,
  l.avg_resolution_seconds,
  l.avg_first_response_seconds,
  l.avg_reply_seconds,
  l.p90_resolution_seconds,
  l.p90_reply_seconds,
  coalesce(ds.duplicate_contact_inbox_days, 0) AS duplicate_contact_inbox_days
FROM conversation_created cc
FULL OUTER JOIN event_counts ec
  ON ec.period = cc.period AND ec.inbox_id = cc.inbox_id
FULL OUTER JOIN latency l
  ON l.period = coalesce(cc.period, ec.period)
 AND l.inbox_id = coalesce(cc.inbox_id, ec.inbox_id)
FULL OUTER JOIN duplicates_summary ds
  ON ds.period = coalesce(cc.period, ec.period, l.period)
 AND ds.inbox_id = coalesce(cc.inbox_id, ec.inbox_id, l.inbox_id)
ORDER BY inbox_id, period;
