# Single History Pilot Tracker

Operational checklist for enabling `lock_to_single_conversation` on pilot inboxes.
Code completion date: 2026-06-24.

## Quick commands

### 1) Baseline / post metrics export

```bash
ACCOUNT_ID=1 \
PILOT_INBOX_IDS_CSV=2,4 \
PRE_START_AT='2026-06-01 00:00:00' \
PRE_END_AT='2026-06-15 00:00:00' \
POST_START_AT='2026-06-15 00:00:00' \
POST_END_AT='2026-06-24 00:00:00' \
OUTPUT_FILE=./pilot_pre_post_2026-06-24.csv \
bin/fork-pilot-single-history-metrics.sh
```

### 2) Enable toggle (per inbox)

Inbox Settings → Channel Preferences → **Reuse and reopen previous conversation** → Save.

Optional SQL (pilot inboxes only, with product approval):

```sql
UPDATE inboxes
SET lock_to_single_conversation = true, updated_at = NOW()
WHERE account_id = :account_id
  AND id IN (:pilot_inbox_ids);
```

### 3) Controlled functional check

1. Create conversation with test contact
2. Resolve conversation
3. Send inbound message from same contact
4. Confirm same conversation reopens (no new `conversations` row)

---

## Pilot metadata

| Field | Value |
|---|---|
| Account ID | |
| Pilot inbox IDs | |
| Baseline window | |
| Post window | |
| Rollback owner | |
| Ops channel | |

---

## Pre-activation (T-24h)

- [x] Baseline metrics export script validated on dev (`bin/fork-pilot-single-history-metrics.sh`)
- [x] Dev sample baseline: `tmp/pilot_dev_baseline.csv` (account 1, inboxes 1,2,4, window 2026-05-01 → 2026-06-24)
- [ ] Baseline metrics exported for staging/production pilot inboxes
- [ ] Baseline CSV saved and shared
- [ ] `conversation_created` automations reviewed for pilot inboxes
- [ ] Integration/webhook owners informed
- [ ] Candidate inboxes verified with toggle OFF
- [ ] No active incident in pilot channels

## Activation (per inbox)

Dev validation (2026-06-24):

| Inbox ID | Toggle | Reuse after resolve | Result |
|---|---|---|---|
| 1 | OFF | No (new conversation) | PASS |
| 2 | ON | Yes (same conversation id) | PASS |

Production rollout:

| Inbox ID | Channel | Owner | Enabled (UTC) | Controlled test | Notes |
|---|---|---|---|---|---|
| | | | | [ ] | |

## Post-activation monitoring (T+24h per inbox)

- [ ] `conversation_opened_count` increased (post vs pre)
- [ ] `conversations_created` reduced (post vs pre)
- [ ] `duplicate_contact_inbox_days` stable
- [ ] `p90_resolution_seconds` / `p90_reply_seconds` within 25% of baseline
- [ ] No critical automation/integration regression

## Go / No-Go

| Inbox ID | Decision | Date | Notes |
|---|---|---|---|
| | GO / NO-GO | | |

## Sign-off

| Stakeholder | Role | Approved | Date | Notes |
|---|---|---|---|---|
| | Product | [ ] | | |
| | Ops | [ ] | | |
| | Enterprise/SLA | [ ] | | SLA continues on reopen acknowledged |

## Rollback (if needed)

1. Disable toggle on affected inbox(es)
2. Communicate rollback timestamp and reason
3. Re-export metrics for rollback window
4. Document root cause before re-enable
