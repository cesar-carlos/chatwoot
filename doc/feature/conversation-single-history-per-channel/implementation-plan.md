# Conversation Single History Per Channel - Implementation Plan

## Context

Chatwoot already supports conversation reuse behavior per inbox via `lock_to_single_conversation`.

- `true`: reuse last conversation for the contact/inbox, including resolved ones (new incoming message reopens it)
- `false` (default): reuse only non-resolved conversation; if last is resolved, create a new conversation

Goal: formalize and expand this behavior consistently across channels, keeping configuration at channel/inbox level.

## Objective

Allow users to choose, per channel/inbox, between:

1. Legacy mode (multiple conversation histories)
2. Single-history mode (resolved conversations are reopened instead of creating new histories)

## Product Decision

- Configuration scope: **Inbox/Channel**
- **Default for new inboxes:** `lock_to_single_conversation = true` (fork migration `20260618120000`)
- No global account-level setting in this phase
- Keep backward compatibility
- **Report behavior is conditional on the toggle:**
  - Toggle OFF → zero change in reports (existing behavior preserved)
  - Toggle ON → per-cycle metrics (resolution time, first response, CSAT adapt to reopen cycles)

## Current State (Technical Summary)

### Key Discovery: The Feature Already Works

The `lock_to_single_conversation` flag, the UI toggle, and the backend logic already exist and are functional for 6 channels. This implementation focuses on:

1. Centralizing duplicated code into a resolver service
2. Extending support to gap channels (LINE)
3. Adding per-cycle metrics so reports are not distorted
4. Improving toggle UX text

### Backend

- Existing field: `inboxes.lock_to_single_conversation` (default `false`)
- Existing channel support (already using this behavior):
  - SMS, Twilio, WhatsApp, Telegram, Facebook, Instagram
  - API/Public flows (via `ConversationBuilder` in specific paths)
- Incoming messages can reopen resolved conversations through `Message#reopen_conversation` callback (`after_create_commit`)
- Conversation status transitions: `open → resolved → open` handled by `Conversation#open!` / `Conversation#resolved!`

### How Conversation Reopen Works (Two-Part Mechanism)

1. **Channel service** finds the conversation (including resolved when flag is `true`)
2. **Message callback** (`Message#reopen_conversation` in `after_create_commit`) automatically calls `conversation.open!` on resolved conversations

No changes needed to this mechanism.

### Frontend

- Existing UI toggle in Inbox Settings:
  - `Settings > Inboxes > [Inbox] > Channel Preferences > Lock to single conversation`
- Manual reopen actions already exist in UI:
  - Conversation header action
  - Context menu action
  - Command bar action

## Code Patterns (Current State)

### Pattern A — Standard (SMS, Twilio, WhatsApp, Telegram)

Identical code copy-pasted across 4 services:

```ruby
def set_conversation
  @conversation = if @inbox.lock_to_single_conversation
                    @contact_inbox.conversations.last
                  else
                    @contact_inbox.conversations.where
                                  .not(status: :resolved).last
                  end
  return if @conversation
  @conversation = ::Conversation.create!(conversation_params)
end
```

Lookup scoped by `@contact_inbox.conversations` (via `contact_inbox_id` FK).

### Pattern B — Facebook/Instagram Builders

Same logic but different query style:

```ruby
def set_conversation_based_on_inbox_config
  if @inbox.lock_to_single_conversation
    Conversation.where(conversation_params).order(created_at: :desc).first || build_conversation
  else
    find_or_build_for_multiple_conversations
  end
end
```

Lookup scoped by `{account_id, inbox_id, contact_id}` instead of `contact_inbox_id`.

Decision: **Keep as-is in Phase 1.** Different query pattern, same functional behavior. Risk of breaking with no functional gain.

### Pattern C — Hardcoded Single-Thread (LINE, TikTok)

Always reuse first conversation, ignoring the flag entirely:

```ruby
# LINE
@conversation = @contact_inbox.conversations.first

# TikTok
@conversation ||= contact_inbox.conversations.first || create_conversation(...)
```

Decision: **Migrate LINE and TikTok to resolver in Phase 1** so inbox-level conversation mode is consistent.

### ConversationBuilder (API/Widget)

When `lock_to_single_conversation = false`, always creates new conversation — doesn't look for non-resolved conversations.

Decision: **Keep as-is.** Intentionally different behavior for API paths.

## Channel Matrix

| Channel | Current behavior | Code path | Phase 1 action | Risk |
|---|---|---|---|---|
| SMS | Respects flag (Pattern A) | `app/services/sms/incoming_message_service.rb` | Migrate to resolver | Low |
| Twilio | Respects flag (Pattern A) | `app/services/twilio/incoming_message_service.rb` | Migrate to resolver | Low |
| WhatsApp | Respects flag (Pattern A) | `app/services/whatsapp/incoming_message_base_service.rb` | Migrate to resolver | Low |
| Telegram | Respects flag (Pattern A) | `app/services/telegram/incoming_message_service.rb` | Migrate to resolver | Low |
| Facebook | Respects flag (Pattern B) | `app/builders/messages/facebook/message_builder.rb` | Migrate to resolver (Worker 1 — planned) | Medium |
| Instagram | Respects flag (Pattern B) | `app/builders/messages/instagram/base_message_builder.rb` | Migrate to resolver (Worker 1 — planned) | Medium |
| LINE | Hardcoded single-thread | `app/services/line/incoming_message_service.rb` | Migrate to resolver (gains flag support) | Medium |
| TikTok | Uses inbox-configurable resolver (implemented) | `app/services/tiktok/message_service.rb` | Completed in current phase | Low |
| Twitter DM | Channel-specific type filter (`direct_message`) | `app/services/twitter/direct_message_parser_service.rb` | Explicitly excluded from Phase 1 (channel-native behavior) | Low |
| Twitter Tweet/thread | Thread routing by `tweet_id`/parent tweet | `app/services/twitter/tweet_parser_service.rb` | Explicitly excluded from Phase 1 (channel-native behavior) | Low |
| Email | Email threading strategy | `app/services/mailbox/conversation_finder_strategies/*` | Keep as-is (out of scope) | — |
| API/Widget | ConversationBuilder | `app/builders/conversation_builder.rb` | Keep as-is | — |

## Report Impact and Per-Cycle Metrics

### The Problem: Distorted Metrics in Multi-Cycle Conversations

When `lock_to_single_conversation = true`, a conversation can be resolved and reopened multiple times. The current reporting system was designed for one-cycle-per-conversation and produces distorted metrics:

| Metric | Current calculation | Problem with multi-cycle | Fix |
|---|---|---|---|
| `avg_resolution_time` | `conversation.updated_at - conversation.created_at` | Second resolution of a 30-day conversation shows 30 days instead of hours | Use cycle start (last reopen) instead of `created_at` |
| `avg_first_response_time` | One `first_response` event per conversation lifetime | Cycles 2+ never generate a first response event | Reset `first_reply_created_at` on reopen |
| CSAT survey | `conversation.messages.where(content_type: :input_csat).present?` | Cycle 2+ never sends CSAT because previous cycle's CSAT already exists | Filter CSAT check to current cycle only |
| `bot_handoff` time | `conversation.updated_at - conversation.created_at` | Same inflation as resolution time | Use cycle start |
| `resolutions_count` | Each resolve creates event | More events per conversation — this is correct behavior | No fix needed |
| `reply_time` | Uses `waiting_since` timestamp | Already per-cycle (correct) | No fix needed |
| `conversations_count` | Uses `conversations.created_at` | Lower count — expected behavior | No fix needed |

### Conditional Behavior: Fixes Only When Toggle Is ON

All per-cycle metric fixes are **conditional on `inbox.lock_to_single_conversation`**:

- **Toggle OFF** → existing calculation preserved (`conversation.created_at` as baseline). Zero change for accounts not using the feature.
- **Toggle ON** → per-cycle calculation activated (cycle start = last reopen time).

This ensures accounts that did not opt in to single-history mode experience no report behavior change.

Implementation pattern used in all custom overlays:

```ruby
cycle_start = Custom::Conversations::ResolutionCycle.start_time(conversation)
```

`Custom::Conversations::ResolutionCycle` is the single source of truth for cycle boundaries (reporting + CSAT).

### Per-Cycle Metrics: How It Works

A **cycle** is the period between a conversation being opened (or reopened) and being resolved.

- Cycle 1 start: `conversation.created_at`
- Cycle N start: last `conversation_opened` reporting event's `event_end_time`

The `conversation_opened` event already exists in `ReportingEventListener` and fires on every reopen. We use it as the cycle boundary marker.

### Report-by-Report Impact Summary

#### Visão Geral (Overview)

| Metric | Impact | Severity |
|---|---|---|
| Conversas Abertas | None — real-time status metric | None |
| Não atendidas | None — same logic | None |
| Tráfego de conversa | Reduction — fewer new conversations created | High (expected) |

#### Conversas

| Metric | Impact |
|---|---|
| `conversations_count` | Reduction — reopen doesn't count as new (expected) |
| `resolutions_count` | Increase — each resolve/reopen/resolve generates event (correct) |
| `incoming_messages_count` | None — counts messages, not conversations |
| `outgoing_messages_count` | None |

#### Agentes

| Metric | Impact |
|---|---|
| Conversas por agente | Reduction — uses `conversations.created_at` |
| `avg_resolution_time` | **Fixed by per-cycle calculation** |
| `avg_first_response_time` | **Fixed by resetting `first_reply_created_at` on reopen** |
| `avg_reply_time` | Minimal — already per-cycle via `waiting_since` |

#### Etiquetas / Caixa de Entrada / Time

Same builders and metrics as Agentes, grouped by label/inbox/team. Same fixes apply.

#### CSAT

- **Fixed by per-cycle CSAT check** — each resolution cycle can trigger a new CSAT survey
- Survey count per conversation lifecycle matches resolution cycle count

#### SLA

- SLA is tied to `AppliedSla` per conversation record
- SLA does NOT reset on reopen — continues on same record
- **Documented limitation** — define SLA policy for reopened threads before Enterprise rollout

#### Robôs (Bots)

| Metric | Impact |
|---|---|
| `bot_resolutions_count` | Uses `.distinct.count` on `conversation_id` — multiple resolutions count as one |
| `bot_handoffs_count` | Prevents duplicates (checks existing event) — no impact |
| Resolution rate | Denominator (conversations) drops more than numerator (unique resolutions) |

## Implementation Plan

### File Change Map

| # | What | Where | Change type |
|---|---|---|---|
| 1 | Setup `custom/` overlay + autoloading | `config/application.rb` + `custom/` dir | FORK (1 line) |
| 2 | `Conversations::Resolver` service (`#perform` + `#find`) | `app/services/conversations/resolver.rb` | New file |
| 3 | Shared resolution cycle helper | `custom/app/services/custom/conversations/resolution_cycle.rb` | Custom overlay |
| 4 | Migrate SMS to resolver | `app/services/sms/incoming_message_service.rb` | FORK marker |
| 5 | Migrate Twilio to resolver | `app/services/twilio/incoming_message_service.rb` | FORK marker |
| 6 | Migrate WhatsApp to resolver | `app/services/whatsapp/incoming_message_base_service.rb` | FORK marker |
| 7 | Migrate Telegram to resolver | `app/services/telegram/incoming_message_service.rb` | FORK marker |
| 8 | Migrate LINE to resolver | `app/services/line/incoming_message_service.rb` | FORK marker |
| 9 | Migrate TikTok to resolver | `app/services/tiktok/message_service.rb` + `messaging_helpers.rb` | FORK marker |
| 10 | `prepend_mod_with` hook on ReportingEventListener | `app/listeners/reporting_event_listener.rb` | FORK (1 line) |
| 11 | `prepend_mod_with` hook on CsatSurveyService | `app/services/csat_survey_service.rb` | FORK (1 line) |
| 12 | Cycle-aware resolution time | `custom/app/listeners/custom/reporting_event_listener.rb` | Custom overlay |
| 13 | Reset `first_reply_created_at` on reopen | `custom/app/models/custom/conversation.rb` | Custom overlay |
| 14 | Cycle-aware CSAT check | `custom/app/services/custom/csat_survey_service.rb` | Custom overlay |
| 15 | Improve UI toggle text | `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` | FORK marker |

### Phase 1 — Resolver + Channel Unification

**Goal:** Eliminate duplicated conversation lookup logic. Zero functional change for Pattern A channels. LINE gains flag support.

1. Create `Conversations::Resolver` service with the standard contract:
   - `#find` — lookup only (no create); `conversation_params` optional
   - `#perform` — find or create; `conversation_params` required when creating
   - `lock_to_single_conversation = true` → newest conversation (including resolved)
   - `lock_to_single_conversation = false` → newest non-resolved conversation
   - Lookup/create serialized via `contact_inbox.with_lock`
2. Replace `set_conversation` in SMS, Twilio, WhatsApp, Telegram, LINE with resolver `#perform`
3. Replace TikTok conversation selection with resolver (`#find` then `#perform` on create to avoid eager TikTok API params on lookup)

### Phase 2 — Per-Cycle Metrics (Conditional on Toggle)

**Goal:** Fix metric distortion for multi-cycle conversations. Only active when `lock_to_single_conversation = true` on the inbox. Accounts without the toggle see zero report behavior change.

#### 2a) Cycle-aware resolution time

Override `ReportingEventListener#conversation_resolved` via custom overlay:

```ruby
def conversation_resolved(event)
  conversation = extract_conversation_and_account(event)[0]

  cycle_start = if conversation.inbox.lock_to_single_conversation?
                  find_cycle_start(conversation)
                else
                  conversation.created_at
                end

  time_to_resolve = conversation.updated_at.to_i - cycle_start.to_i
  # ... rest uses cycle_start for event_start_time and business_hours
end
```

Same conditional applied to `conversation_bot_handoff`.

#### 2b) Per-cycle first response

Override conversation reopen behavior via `Custom::Conversation` prepend:

```ruby
# Only reset when lock_to_single_conversation is enabled on the inbox
def reset_cycle_metrics_on_reopen
  return unless saved_change_to_status?
  return unless status_previously_was == 'resolved'
  return unless inbox.lock_to_single_conversation?

  update_column(:first_reply_created_at, nil)
end
```

The existing `Message#dispatch_create_events` flow will naturally create a new `first_response` reporting event for the new cycle.

#### 2c) Per-cycle CSAT

Override `CsatSurveyService#csat_already_sent?` via custom overlay:

```ruby
def csat_already_sent?
  return super unless conversation.inbox.lock_to_single_conversation?

  # Only check for CSAT messages created after the last reopen
  scope = conversation.messages.where(content_type: :input_csat)
  last_opened_at = last_cycle_start_time(conversation)
  scope = scope.where('created_at > ?', last_opened_at) if last_opened_at
  scope.exists?
end
```

### Phase 3 — UI/UX

1. Improve toggle description text in `inboxMgmt.json`:
   - Current: "Enable or disable multiple conversations for the same contact in this inbox"
   - New: "When enabled, new messages from the same contact will reopen the previous conversation instead of creating a new one. Metrics are tracked per resolution cycle."
2. Show non-blocking amber banner when user selects single-history mode and active `conversation_created` automation rules apply to the inbox (or all inboxes). Uses existing `automations/get` store action — no new backend endpoint.

### Phase 4 — Validation and Rollout

1. Run baseline SQL queries (see Appendix) on pilot inboxes
2. Enable `lock_to_single_conversation` on pilot inboxes
3. Run post-change queries after 7-14 days
4. Validate: resolution time per-cycle, first response per-cycle, CSAT per-cycle
5. Expand by channel cohorts

## Fork Strategy

### `custom/` Overlay Structure

```
custom/
├── app/
│   ├── listeners/
│   │   └── custom/
│   │       └── reporting_event_listener.rb    # cycle-aware resolution time + bot handoff
│   ├── models/
│   │   └── custom/
│   │       └── conversation.rb                # reset first_reply_created_at on reopen
│   └── services/
│       └── custom/
│           ├── conversations/
│           │   └── resolution_cycle.rb        # shared cycle start helper (reporting + CSAT)
│           └── csat_survey_service.rb          # cycle-aware CSAT check
```

### Hook Points (FORK markers in upstream files)

```ruby
# app/listeners/reporting_event_listener.rb
ReportingEventListener.prepend_mod_with('ReportingEventListener')  # FORK: per-cycle metrics

# app/services/csat_survey_service.rb
CsatSurveyService.prepend_mod_with('CsatSurveyService')  # FORK: per-cycle CSAT

# app/models/conversation.rb — already has:
Conversation.prepend_mod_with('Conversation')  # existing hook, no change needed
```

### Autoloading

Add to `config/application.rb`:

```ruby
config.eager_load_paths += Dir["#{Rails.root}/custom/app/**"]  # FORK: custom overlay autoloading
```

## Risks and Mitigations

1. **Metric interpretation drift**
   - Mitigation: per-cycle metrics fix + baseline comparison + rollout notes
2. **Channel inconsistency**
   - Mitigation: centralized resolver for Phase 1 channels
3. **Automation side effects**
   - Mitigation: verify rules dependent on `conversation_created` and `conversation_opened`
4. **SLA lifecycle on reopened threads**
   - Mitigation: validate with Enterprise accounts before expansion
5. **Cycle start detection edge case (no `conversation_opened` event)**
   - Mitigation: fall back to `conversation.created_at` (first cycle behavior)

## Test Plan

### Resolver Tests

- `lock_to_single_conversation = true`:
  - resolved conversation exists → same conversation returned
  - no conversation exists → new conversation created
- `lock_to_single_conversation = false`:
  - resolved conversation exists → new conversation created
  - non-resolved conversation exists → same conversation returned
  - no conversation exists → new conversation created

### Channel Service Tests

- SMS, Twilio, WhatsApp, Telegram: zero functional change (resolver produces same result)
- LINE: gains flag support (test both `true` and `false`)

### Per-Cycle Metric Tests

- `conversation_resolved` event:
  - first resolution → `value = updated_at - created_at` (unchanged)
  - second resolution after reopen → `value = updated_at - reopen_time` (cycle-aware)
- `first_response` event:
  - first cycle → event created normally
  - second cycle after reopen → `first_reply_created_at` reset, new event created
- CSAT:
  - first resolution → CSAT sent
  - second resolution after reopen → CSAT sent again (current cycle check)

### Regression Tests

- Manual reopen from UI remains functional
- Command bar reopen remains functional
- `reply_time` metric unchanged (already per-cycle)

## Definition of Done

- [x] `Conversations::Resolver` implemented (`#find` + `#perform`) and used by SMS, Twilio, WhatsApp, Telegram, LINE, TikTok
- [x] `Custom::Conversations::ResolutionCycle` centralizes cycle boundary logic
- [x] Per-cycle resolution time implemented via custom overlay
- [x] Per-cycle first response implemented (reset `first_reply_created_at` on reopen)
- [x] Per-cycle CSAT implemented via custom overlay
- [x] `custom/` overlay autoloading configured
- [x] UI toggle text improved
- [x] Automation rules warning when enabling single-history toggle (inbox settings)
- [x] Inbox factory `:single_history` trait for specs
- [x] All test scenarios passing
- [ ] Baseline SQL queries executed on pilot inboxes

## Delivery Checklist

- [x] `custom/` directory created and autoloading configured
- [x] Resolver service created and channel services migrated
- [x] Custom overlay modules created (ReportingEventListener, Conversation, CsatSurveyService)
- [x] `prepend_mod_with` hooks added with FORK markers
- [x] i18n text updated with FORK marker
- [x] Automation warning banner in inbox settings (EN + PT-BR)
- [x] Inbox factory `:single_history` trait
- [ ] Pilot rollout completed with monitored metrics

## Pilot Readiness Snapshot

### Engineering status (code complete)

- [x] Inbox-level toggle behavior implemented for Phase 1 channels: SMS, Twilio, WhatsApp, Telegram, LINE, TikTok
- [x] Reopen/create selection centralized via `Conversations::Resolver`
- [x] Per-cycle reporting behavior implemented when single-history mode is ON
- [x] Per-cycle CSAT behavior implemented when single-history mode is ON
- [x] Existing behavior preserved when single-history mode is OFF
- [x] Twitter and Email intentionally excluded from Phase 1 (documented)

### Validation status (tests/lint)

- [x] Focused specs for resolver and channel migrations passing
- [x] Focused specs for reporting/CSAT cycle behavior passing
- [x] Focused regression spec for Twitter webhook path passing
- [x] Lint checks clean on changed files
- [x] Post-lint-fix validation rerun completed (`rubocop` on changed feature files + focused `rspec`: `53 examples, 0 failures`)

## Audit (2026-06-18)

Engineering review to align implementation with project rules (single responsibility, no duplicate logic, fork-safe overlays).

### Bugs fixed

| Issue | Location | Fix |
|---|---|---|
| LINE kept legacy `set_conversation` inline logic **and** called resolver (dead code, non-deterministic `.last`) | `app/services/line/incoming_message_service.rb` | Use resolver `#perform` only (same as SMS/Twilio/etc.) |
| TikTok duplicated resolver logic in `MessageService` + `MessagingHelpers`; create path could race | `app/services/tiktok/*` | `#find` then `#perform` on create; read-status lookup delegates to resolver `#find` |
| Reporting override used `conversation.updated_at` instead of `event.timestamp` | `custom/.../reporting_event_listener.rb` | Align with upstream listener contract |
| Reporting override omitted `safe_rollup` | `custom/.../reporting_event_listener.rb` | Call `safe_rollup` after save (resolved + bot handoff) |
| Cycle start logic duplicated in reporting + CSAT overlays | custom overlays | Extract `Custom::Conversations::ResolutionCycle` |
| Resolver required `conversation_params` on lookup-only paths (TikTok API side effect) | `Conversations::Resolver` | `conversation_params` optional for `#find`; required only on create via `#perform` |

### Anti-patterns removed

- **Duplicate logic** — TikTok/LINE no longer maintain parallel conversation-selection branches
- **Shotgun surgery** — cycle boundary rule lives in one module consumed by reporting and CSAT
- **Dead code** — removed unused `create_conversation` helper from TikTok messaging helpers

### Intentional differences preserved

| Area | Behavior |
|---|---|
| TikTok read receipts | `find_conversation` uses resolver `#find`, then falls back to latest thread when all conversations are resolved (read-status only; does not create) |
| Facebook/Instagram | Pattern B unchanged (pre-existing inbox flag support) |
| API/Widget `ConversationBuilder` | Unchanged (intentionally different) |
| Twitter / Email | Excluded from Phase 1 |

### Validation after audit

- `rubocop` clean on all touched files
- Focused `rspec`: **53 examples, 0 failures** (resolver, LINE, TikTok, reporting, CSAT cycle, conversation reopen reset)

### Operational status (pending to execute pilot)

- [ ] Run baseline SQL for selected pilot inboxes (pre window)
- [ ] Execute pilot activation runbook inbox-by-inbox
- [ ] Run post window SQL and compare pre/post
- [ ] Confirm go/no-go criteria and thresholds
- [ ] Complete pilot closeout sign-off

### Follow-up (2026-06-18 orchestration — Worker 3)

| Item | Status | Notes |
|---|---|---|
| Automation warning on toggle ON | Done | `SingleHistoryAutomationWarning.vue` + `useSingleHistoryAutomationWarning.js`; queries `automations/get` store; EN + PT-BR i18n |
| Inbox factory `:single_history` trait | Done | `spec/factories/inboxes.rb`; used in `resolver_spec` |
| FB/IG resolver migration | Planned (Worker 1) | Pattern B builders still use inline lookup; intended to migrate to `Conversations::Resolver` for consistency |
| Static i18n-only automation note | Not needed | Dynamic warning implemented via existing store API |

**Phase 2 (deferred):** Per-rule inbox scoping preview in banner (e.g. link to filtered automation list), or backend endpoint if store payload becomes too heavy for settings page.

## Implementation Progress Log

- 2026-02-25: Implemented `Conversations::Resolver` and migrated SMS, Twilio, WhatsApp, Telegram, LINE to centralized selection logic.
- 2026-02-25: Added custom overlay modules for cycle-aware reporting (`conversation_resolved`, `conversation_bot_handoff`), per-cycle CSAT check, and `first_reply_created_at` reset on reopen.
- 2026-02-25: Added `prepend_mod_with` hooks and `custom/` eager loading (`custom/lib` + `custom/app/**`).
- 2026-02-25: Updated Inbox Settings toggle copy to clarify reopen behavior and report mode linkage.
- 2026-02-25: Ran focused specs for changed areas (`142 examples, 0 failures`).
- 2026-02-25: Extended TikTok channel to honor `lock_to_single_conversation` using `Conversations::Resolver` and added ON/OFF behavior specs.
- 2026-02-25: Added dedicated specs for `Conversations::Resolver` and for reopen cycle reset on `Conversation#first_reply_created_at`.
- 2026-02-25: Updated CSAT UI notes to reflect default (per conversation) vs single-history mode (per resolution cycle).
- 2026-02-25: Added concurrency mitigation in `Conversations::Resolver` using `contact_inbox.with_lock` to serialize lookup/create and reduce duplicate thread races.
- 2026-02-25: Fixed RuboCop offenses in feature-touched files and reran focused validation (`rubocop` clean + `rspec` clean with `52 examples, 0 failures`).
- 2026-02-25: Manual validation in channel settings confirmed expected runtime behavior with toggle ON (`lock_to_single_conversation`): resolved conversation reopens on new inbound message.
- 2026-06-18: Engineering audit — fixed LINE/TikTok duplicate resolver logic, reporting `event.timestamp` + `safe_rollup` gaps, extracted `Custom::Conversations::ResolutionCycle`, added resolver `#find` with optional params. Focused validation: `53 examples, 0 failures`.
- 2026-06-18: Worker 3 — automation warning banner on single-history toggle (uses existing automations store), `:single_history` factory trait, EN/PT-BR ops copy.

## Open Questions

- [x] Phase 1 mandatory channels defined for implementation baseline: SMS, Twilio, WhatsApp, Telegram, LINE, TikTok.
- [x] Configuration scope defined for this release: inbox/channel-level only (account-level default postponed as future enhancement).
- [x] SLA policy defined for Phase 1 pilot: continue SLA lifecycle on reopen (no reset).
- [ ] Formal business sign-off recorded (Product/Ops/Enterprise) using the checklist below.

## Recommended Decision Closure (Business Sign-off)

To move from "plan complete" to "pilot execution", use the following defaults unless product/ops explicitly override.

1. **Phase 1 channel scope**
   - Decision: keep scope as **SMS, Twilio, WhatsApp, Telegram, LINE, TikTok**.
   - Rationale: implementation + tests already completed for this set with lowest additional rollout risk.

2. **Configuration level**
   - Decision: keep **inbox/channel-level only** in this release.
   - Rationale: this is already supported natively via `lock_to_single_conversation`, gives safer progressive rollout, and avoids account-wide blast radius.
   - Future option: add account-level default later as a separate enhancement (channel can still override).

3. **SLA policy on reopened threads**
   - Decision (Phase 1): **continue existing SLA lifecycle** on the same conversation record (no SLA reset on reopen).
   - Rationale: matches current `AppliedSla` behavior and avoids introducing SLA regressions during initial rollout.
   - Guardrail: treat this as a documented limitation for single-history pilot; revisit only after pilot stabilization with explicit Enterprise validation.

### Final Go/No-Go Input Checklist

- [ ] Product approves the three decisions above as Phase 1 baseline.
- [ ] Ops confirms pilot inbox list and owners.
- [ ] Engineering confirms baseline/pre-post SQL windows and thresholds.
- [ ] Enterprise/SLA stakeholders acknowledge "SLA continues on reopen" policy for pilot.

## Explicit Exclusions (Phase 1)

- Twitter DM and Twitter Tweet/thread remain channel-native in this phase.
- Rationale:
  - DM parser intentionally scopes by `additional_attributes.type = direct_message`.
  - Tweet parser intentionally scopes by `additional_attributes.tweet_id` plus parent tweet routing.
  - Applying generic contact-inbox resolver to Twitter paths can risk mixing DM and Tweet threads.
- Future work (optional): introduce a Twitter-specific resolver contract before unifying behavior with inbox toggle.

## Appendix - Baseline SQL (Pilot Before/After)

Use these queries in staging/production replicas before enabling the setting and again after rollout in pilot inboxes.

### Parameters

- `:account_id` -> target account
- `:pilot_inbox_ids` -> inbox id list (example: `10, 11, 12`)
- `:start_at` and `:end_at` -> analysis window (recommended: 7-14 days)

### 1) Conversation creation volume by inbox/day

```sql
SELECT
  c.inbox_id,
  DATE_TRUNC('day', c.created_at) AS day,
  COUNT(*) AS conversations_created
FROM conversations c
WHERE c.account_id = :account_id
  AND c.inbox_id IN (:pilot_inbox_ids)
  AND c.created_at >= :start_at
  AND c.created_at < :end_at
GROUP BY c.inbox_id, DATE_TRUNC('day', c.created_at)
ORDER BY day, c.inbox_id;
```

### 2) Reopen vs created events (thread reuse signal)

```sql
SELECT
  re.inbox_id,
  DATE_TRUNC('day', re.created_at) AS day,
  re.name,
  COUNT(*) AS events_count
FROM reporting_events re
WHERE re.account_id = :account_id
  AND re.inbox_id IN (:pilot_inbox_ids)
  AND re.created_at >= :start_at
  AND re.created_at < :end_at
  AND re.name IN ('conversation_created', 'conversation_opened', 'conversation_resolved')
GROUP BY re.inbox_id, DATE_TRUNC('day', re.created_at), re.name
ORDER BY day, re.inbox_id, re.name;
```

### 3) Reuse ratio by inbox (opened / created events)

```sql
SELECT
  re.inbox_id,
  SUM(CASE WHEN re.name = 'conversation_opened' THEN 1 ELSE 0 END)::float
    / NULLIF(SUM(CASE WHEN re.name = 'conversation_created' THEN 1 ELSE 0 END), 0) AS reopen_to_create_ratio
FROM reporting_events re
WHERE re.account_id = :account_id
  AND re.inbox_id IN (:pilot_inbox_ids)
  AND re.created_at >= :start_at
  AND re.created_at < :end_at
  AND re.name IN ('conversation_created', 'conversation_opened')
GROUP BY re.inbox_id
ORDER BY re.inbox_id;
```

### 4) Resolution and first response averages by inbox

```sql
SELECT
  re.inbox_id,
  AVG(CASE WHEN re.name = 'conversation_resolved' THEN re.value END) AS avg_resolution_seconds,
  AVG(CASE WHEN re.name = 'first_response' THEN re.value END) AS avg_first_response_seconds,
  AVG(CASE WHEN re.name = 'reply_time' THEN re.value END) AS avg_reply_seconds
FROM reporting_events re
WHERE re.account_id = :account_id
  AND re.inbox_id IN (:pilot_inbox_ids)
  AND re.created_at >= :start_at
  AND re.created_at < :end_at
  AND re.name IN ('conversation_resolved', 'first_response', 'reply_time')
GROUP BY re.inbox_id
ORDER BY re.inbox_id;
```

### 5) Distribution check (p50/p90) for latency shifts

```sql
SELECT
  re.inbox_id,
  re.name,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY re.value) AS p50_seconds,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY re.value) AS p90_seconds
FROM reporting_events re
WHERE re.account_id = :account_id
  AND re.inbox_id IN (:pilot_inbox_ids)
  AND re.created_at >= :start_at
  AND re.created_at < :end_at
  AND re.name IN ('conversation_resolved', 'first_response', 'reply_time')
GROUP BY re.inbox_id, re.name
ORDER BY re.inbox_id, re.name;
```

### 6) New inbound messages to resolved conversations (pre/post behavior indicator)

```sql
SELECT
  m.inbox_id,
  DATE_TRUNC('day', m.created_at) AS day,
  COUNT(*) AS inbound_on_resolved
FROM messages m
JOIN conversations c ON c.id = m.conversation_id
WHERE c.account_id = :account_id
  AND m.inbox_id IN (:pilot_inbox_ids)
  AND m.message_type = 0
  AND c.status = 1
  AND m.created_at >= :start_at
  AND m.created_at < :end_at
GROUP BY m.inbox_id, DATE_TRUNC('day', m.created_at)
ORDER BY day, m.inbox_id;
```

### 7) Duplicate thread detector for same contact inbox/day

```sql
SELECT
  c.inbox_id,
  c.contact_inbox_id,
  DATE_TRUNC('day', c.created_at) AS day,
  COUNT(*) AS conversations_created_same_day
FROM conversations c
WHERE c.account_id = :account_id
  AND c.inbox_id IN (:pilot_inbox_ids)
  AND c.created_at >= :start_at
  AND c.created_at < :end_at
GROUP BY c.inbox_id, c.contact_inbox_id, DATE_TRUNC('day', c.created_at)
HAVING COUNT(*) > 1
ORDER BY conversations_created_same_day DESC, day;
```

### Suggested pilot execution

1. Run all queries for a pre-change baseline (7-14 days).
2. Enable `lock_to_single_conversation` only on pilot inboxes.
3. Re-run for an equal post-change window.
4. Compare:
   - `conversation_created` downtrend (expected)
   - `conversation_opened` uptrend (expected)
   - latency metrics (`avg`, `p50`, `p90`) for regressions
   - duplicate detector anomalies (should not spike)

### 8) Single pre/post comparison query (one command per pilot)

Use this query to compare pre and post windows in one result set.

```sql
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
```

Parameters:

- `:account_id` -> account id
- `:pilot_inbox_ids_csv` -> comma-separated inbox IDs (example: `10,11,12`)
- `:pre_start_at`, `:pre_end_at` -> baseline window
- `:post_start_at`, `:post_end_at` -> post-enable window

### 9) Ready-to-run example (psql)

Use this block directly in `psql` (replace sample values as needed):

```sql
WITH params AS (
  SELECT
    123::bigint AS account_id,
    '2026-02-01 00:00:00'::timestamp AS pre_start_at,
    '2026-02-08 00:00:00'::timestamp AS pre_end_at,
    '2026-02-08 00:00:00'::timestamp AS post_start_at,
    '2026-02-15 00:00:00'::timestamp AS post_end_at
),
windows AS (
  SELECT 'pre' AS period, pre_start_at AS start_at, pre_end_at AS end_at FROM params
  UNION ALL
  SELECT 'post' AS period, post_start_at AS start_at, post_end_at AS end_at FROM params
),
pilot_inboxes AS (
  SELECT unnest(string_to_array('10,11,12', ','))::bigint AS inbox_id
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
```

## Pilot Runbook (Operational)

This section is guidance/reference.
Execution tracking source of truth: use the checklist in `Pilot Activation Checklist (Copy/Paste Template)`.

### Scope and Activation Order

1. Start only with low-risk channels that already use standard selection behavior:
   - SMS
   - Twilio
   - WhatsApp
   - Telegram
   - LINE
2. Select 2-3 pilot inboxes with moderate volume (not peak-volume inboxes).
3. Enable `lock_to_single_conversation` one inbox at a time, with at least 24h observation between each activation.

### Preconditions (Go to Pilot)

- Baseline SQL captured for at least 7 days.
- Support/operations informed that conversation volume KPIs will shift by design.
- Automation rules reviewed for heavy use of `conversation_created`.
- Integrations/webhooks reviewed for assumptions tied to new conversation creation counts.
- Rollback owner and communication channel defined.

### Day 0 Checklist (Before Enabling)

1. Run appendix queries for baseline windows (`:start_at`, `:end_at`).
2. Save baseline snapshots by inbox in a shared sheet/doc.
3. Confirm toggle is `OFF` for all candidate inboxes.
4. Confirm no incident/noise in those channels in the last 24h.

### Enablement Procedure (Per Inbox)

1. Enable `lock_to_single_conversation` in Inbox Settings.
2. Send a controlled test sequence:
   - create conversation
   - resolve conversation
   - send inbound message from same contact
   - verify conversation reopens (no new conversation row)
3. Validate report behavior in next data refresh cycle:
   - `conversation_opened` event appears
   - `conversation_resolved` value reflects cycle start when toggle is ON
   - CSAT can be sent once per cycle, not once per lifetime
4. Monitor for at least 24h before enabling next inbox.

### Go / No-Go Criteria (Per Inbox)

**Go if all are true:**

- No spike in duplicate conversation detector query.
- Reopen behavior is consistent for sampled contacts.
- No critical automation or integration breakage reported.
- Latency metrics remain within acceptable band versus baseline.

**No-Go / Pause if any is true:**

- Duplicate detector shows sustained anomaly.
- Reopen behavior is inconsistent across normal traffic.
- Critical workflow depending on `conversation_created` breaks.
- Support tickets indicate major reporting confusion not mitigated by communication.

### Suggested Thresholds (Initial)

- Duplicate thread anomaly: `conversations_created_same_day` increases > 20% for same `contact_inbox_id` cohort versus baseline.
- Unexpected conversation creation: `conversation_created` does not reduce at all after enablement in ON inboxes.
- Reopen signal missing: `conversation_opened` does not show expected increase within 24-48h.
- Latency regression: `p90` for `conversation_resolved` or `reply_time` degrades > 25% versus baseline for 2 consecutive days.

### Rollback Procedure

1. Disable `lock_to_single_conversation` for affected inbox(es).
2. Communicate rollback event to support/ops with timestamp.
3. Re-run baseline queries for rollback window to confirm stabilization.
4. Record root cause and corrective action before attempting re-enable.

### Post-Pilot Exit Criteria

- 7+ days stable operation across all pilot inboxes.
- No unresolved critical issue linked to reopen mode.
- KPI shifts documented and accepted by support/operations.
- Product sign-off to expand to next inbox cohort.

## Pilot Activation Checklist (Copy/Paste Template)

Use this block as the canonical operational tracker on activation day.

### Pilot Metadata

- Account ID: `<account_id>`
- Pilot Inbox IDs: `<inbox_id_1>, <inbox_id_2>, <inbox_id_3>`
- Baseline window start (`:start_at`): `<YYYY-MM-DD HH:MM:SS UTC>`
- Baseline window end (`:end_at`): `<YYYY-MM-DD HH:MM:SS UTC>`
- Post window start: `<YYYY-MM-DD HH:MM:SS UTC>`
- Post window end: `<YYYY-MM-DD HH:MM:SS UTC>`
- Rollback owner: `<name>`
- Ops communication channel: `<slack/teams/email>`

### Pre-Activation (T-24h)

- [ ] Baseline SQL appendix queries executed for all pilot inboxes
- [ ] Baseline snapshots saved and shared
- [ ] Automation rules reviewed (`conversation_created`, `conversation_opened`, `message_created`)
- [ ] Integration/webhook owners informed
- [ ] Candidate inboxes verified with toggle OFF
- [ ] No active incident in pilot channels

### Activation (T0)

- [x] Enable `lock_to_single_conversation` on inbox `<inbox_id_1>`
- [x] Controlled test passed on `<inbox_id_1>`:
  - [x] create conversation
  - [x] resolve conversation
  - [x] inbound message from same contact
  - [x] same conversation reopened (no new conversation row)
- [ ] Log activation timestamp for `<inbox_id_1>`

### Post-Activation Monitoring (T+24h)

- [ ] Query check: `conversation_opened` increased as expected
- [ ] Query check: `conversation_created` reduced as expected
- [ ] Query check: duplicate detector stable (`conversations_created_same_day`)
- [ ] Query check: latency within threshold (`p90` delta <= 25%)
- [ ] Manual sample: reopen behavior correct on real traffic
- [ ] No critical automation/integration regression reported

### Go/No-Go Decision (Inbox `<inbox_id_1>`)

- [ ] GO: proceed to next inbox in pilot
- [ ] NO-GO: pause rollout and investigate
- Notes: `<decision notes>`

### Rollback (If Needed)

- [ ] Disable `lock_to_single_conversation` on affected inbox(es)
- [ ] Communicate rollback timestamp and reason
- [ ] Re-run key baseline queries for rollback window
- [ ] Capture root cause and corrective actions

### Pilot Closeout (After all pilot inboxes)

- [ ] 7+ days stable across pilot inboxes
- [ ] KPI shifts documented and accepted
- [ ] Product/ops sign-off recorded
- [ ] Expansion plan to next cohort approved

### Inbox-by-Inbox Rollout Sheet (Repeatable Block)

Copy this block once per inbox in the pilot batch:

```md
#### Inbox `<inbox_id>`

- Channel: `<SMS|Twilio|WhatsApp|Telegram|LINE>`
- Owner: `<name>`
- Enable timestamp (UTC): `<YYYY-MM-DD HH:MM:SS>`

Pre-check
- [ ] Toggle currently OFF
- [ ] Baseline data captured for this inbox
- [ ] No active incident in last 24h

Activation
- [ ] Toggle set to ON
- [ ] Controlled flow validated:
  - [ ] create -> resolve -> inbound -> reopen same conversation

T+24h Monitoring
- [ ] `conversation_opened` increased
- [ ] `conversation_created` reduced
- [ ] Duplicate detector stable
- [ ] `p90` latency delta within threshold
- [ ] No critical automation/integration incident

Decision
- [ ] GO
- [ ] NO-GO
- Notes: `<decision notes>`

Rollback (if NO-GO)
- [ ] Toggle reverted to OFF
- [ ] Rollback communicated
- [ ] Post-rollback query checks completed
```

### Inbox-by-Inbox Rollout Sheet (Examples A/B/C)

Use these as starter entries and replace placeholders.

```md
#### Inbox A `<inbox_id_a>`

- Channel: `<SMS>`
- Owner: `<owner_a>`
- Enable timestamp (UTC): `<YYYY-MM-DD HH:MM:SS>`

Pre-check
- [ ] Toggle currently OFF
- [ ] Baseline data captured for this inbox
- [ ] No active incident in last 24h

Activation
- [ ] Toggle set to ON
- [ ] Controlled flow validated:
  - [ ] create -> resolve -> inbound -> reopen same conversation

T+24h Monitoring
- [ ] `conversation_opened` increased
- [ ] `conversation_created` reduced
- [ ] Duplicate detector stable
- [ ] `p90` latency delta within threshold
- [ ] No critical automation/integration incident

Decision
- [ ] GO
- [ ] NO-GO
- Notes: `<decision notes_a>`

Rollback (if NO-GO)
- [ ] Toggle reverted to OFF
- [ ] Rollback communicated
- [ ] Post-rollback query checks completed

#### Inbox B `<inbox_id_b>`

- Channel: `<WhatsApp>`
- Owner: `<owner_b>`
- Enable timestamp (UTC): `<YYYY-MM-DD HH:MM:SS>`

Pre-check
- [ ] Toggle currently OFF
- [ ] Baseline data captured for this inbox
- [ ] No active incident in last 24h

Activation
- [ ] Toggle set to ON
- [ ] Controlled flow validated:
  - [ ] create -> resolve -> inbound -> reopen same conversation

T+24h Monitoring
- [ ] `conversation_opened` increased
- [ ] `conversation_created` reduced
- [ ] Duplicate detector stable
- [ ] `p90` latency delta within threshold
- [ ] No critical automation/integration incident

Decision
- [ ] GO
- [ ] NO-GO
- Notes: `<decision notes_b>`

Rollback (if NO-GO)
- [ ] Toggle reverted to OFF
- [ ] Rollback communicated
- [ ] Post-rollback query checks completed

#### Inbox C `<inbox_id_c>`

- Channel: `<Telegram>`
- Owner: `<owner_c>`
- Enable timestamp (UTC): `<YYYY-MM-DD HH:MM:SS>`

Pre-check
- [ ] Toggle currently OFF
- [ ] Baseline data captured for this inbox
- [ ] No active incident in last 24h

Activation
- [ ] Toggle set to ON
- [ ] Controlled flow validated:
  - [ ] create -> resolve -> inbound -> reopen same conversation

T+24h Monitoring
- [ ] `conversation_opened` increased
- [ ] `conversation_created` reduced
- [ ] Duplicate detector stable
- [ ] `p90` latency delta within threshold
- [ ] No critical automation/integration incident

Decision
- [ ] GO
- [ ] NO-GO
- Notes: `<decision notes_c>`

Rollback (if NO-GO)
- [ ] Toggle reverted to OFF
- [ ] Rollback communicated
- [ ] Post-rollback query checks completed
```

## Pilot Start Pack (Quick Ops)

Use this section as a fast-start companion to the canonical checklist above.
Do not use this section as the primary progress tracker.

### 1) Set pilot variables

- `account_id`: `1`
- `pilot_inbox_ids_csv`: `<inbox_id_1,inbox_id_2,inbox_id_3>`
- `pre_start_at`: `2026-02-18 00:00:00`
- `pre_end_at`: `2026-02-25 00:00:00`
- `post_start_at`: `2026-02-25 00:00:00`
- `post_end_at`: `2026-03-04 00:00:00`

### 1.1) Today preset (ready to run)

Use this preset for immediate pilot execution and only replace inbox ids:

- `account_id`: `1`
- `pilot_inbox_ids_csv`: `<replace_with_real_ids>` (example format: `10,11,12`)
- `pre_start_at`: `2026-02-18 00:00:00`
- `pre_end_at`: `2026-02-25 00:00:00`
- `post_start_at`: `2026-02-25 00:00:00`
- `post_end_at`: `2026-03-04 00:00:00`

### 2) Command 1 - Baseline (pre window)

- Run section `9) Ready-to-run example (psql)` with:
  - `pre_*` set to baseline window
  - `post_*` set to expected pilot observation window (or temporary placeholders)
- Save output as: `pilot_pre_<date>.csv`

### 3) Command 2 - Enable toggle on first inbox

- In Inbox Settings for `<inbox_id_1>`:
  - Enable `lock_to_single_conversation`
- Record activation timestamp in UTC.

### 4) Command 3 - Controlled functional check

- Execute one manual flow on `<inbox_id_1>`:
  - create conversation
  - resolve conversation
  - send inbound message from same contact
  - confirm same conversation reopens (no new conversation row)

### 5) Command 4 - Post window measurement

- Re-run section `9) Ready-to-run example (psql)` after observation window.
- Save output as: `pilot_post_<date>.csv`

### 6) Command 5 - Go/No-Go decision

- Compare pre vs post outputs for `<inbox_id_1>`:
  - `conversation_opened_count` uptrend (expected)
  - `conversations_created` downtrend (expected)
  - `duplicate_contact_inbox_days` stable
  - `p90_resolution_seconds` and `p90_reply_seconds` within threshold
- Decision:
  - GO -> enable next inbox
  - NO-GO -> rollback toggle and investigate

### Day-of checklist (short)

- [ ] Baseline query output saved (matches `Pre-Activation` in canonical checklist)
- [ ] Toggle enabled on target inbox (matches `Activation`)
- [ ] Manual reopen flow validated (matches `Activation`)
- [ ] Post query output saved (matches `Post-Activation Monitoring`)
- [ ] Go/No-Go recorded with owner and timestamp (matches `Go/No-Go Decision`)

### 7) Copy/paste `psql` script (`\set` + CSV export)

Paste and run this block directly (replace only inbox ids first):

```bash
psql "$DATABASE_URL" <<'SQL'
\set account_id 1
\set pilot_inbox_ids_csv '''10,11,12'''
\set pre_start_at '''2026-02-18 00:00:00'''
\set pre_end_at '''2026-02-25 00:00:00'''
\set post_start_at '''2026-02-25 00:00:00'''
\set post_end_at '''2026-03-04 00:00:00'''
\set output_file '''./pilot_pre_post_2026-03-04.csv'''

\copy (
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
ORDER BY inbox_id, period
) TO :output_file WITH CSV HEADER;
SQL
```
