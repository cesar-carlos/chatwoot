# Audio Transcription (Groq) - Implementation Plan

## Objective
- Replicate the strong UX from the backup fork (audio player transcribe action + inline transcript + token setup screen).
- Adapt implementation to this fork's architecture with maximum merge safety and minimal upstream conflict risk.
- Keep delivery internal to this fork only (no upstream PR), with controlled branch integration into `main`.

## Scope Decisions
- Provider strategy: Groq token per user profile.
- Fork strategy: minimal core edits, isolate behavior where possible, and mark divergent lines with `FORK:` tags.
- Delivery strategy: feature branch -> internal review -> integration branch from updated `main` -> merge to fork `main`.
- Security strategy: do not index `users.groq_token`, never log token values, and keep token masked in UI.
- API strategy: prefer `attachment_id` server-side transcription path; keep multipart only as fallback.
- Data strategy: unify transcript cache contract while keeping backward compatibility with legacy `transcribed_text`.

## Phase 0 - Branch and Workflow Setup
- Create and protect the branch flow before coding.
- Ensure no upstream PR workflow is used.

### TODO Checklist
- [x] Create feature branch from fork `main` (example: `feat/audio-transcription-groq`).
- [x] Confirm repository remotes and team workflow are fork-internal only.
- [x] Define integration branch name for final sync (example: `merge/audio-transcription-main`).
- [x] Confirm final merge policy (regular merge only, no destructive history rewrite).

## Phase 1 - Current State Mapping and Merge-Safe Design
- Lock down exactly what already exists in current codebase.
- Define minimum-delta changes for controllers, serializer, settings UI, and message audio chip.

### TODO Checklist
- [x] Map current automatic transcription flow in `enterprise/` and identify reusable parts.
- [x] Document all required touchpoints in `app/` and `enterprise/`.
- [x] Mark files where core edits are unavoidable and plan `FORK:` markers.
- [x] Define canonical transcript metadata contract (single source of truth) with compatibility reader for legacy keys.
- [x] Define explicit transcription states (`pending`, `processing`, `success`, `error`) and when each state is persisted.
- [x] Define idempotency strategy per `attachment_id` (lock key + TTL + duplicate request behavior).

## Phase 2 - User Groq Token Configuration
- Add user token persistence and profile UI setup matching desired UX.

### TODO Checklist
- [x] Add migration for `users.groq_token` (without index).
- [x] Permit `groq_token` in profile update params.
- [x] Expose `groq_token` in user serializer payload.
- [x] Add `GroqToken` UI section in profile settings page.
- [x] Ensure token field remains masked and is never printed in client logs/errors.
- [x] Ensure backend filtered parameters include `groq_token` to prevent sensitive logging.
- [x] Add frontend i18n keys in `en.json`.
- [ ] Add backend i18n keys in `en.yml` (only if needed by API responses).

## Phase 3 - Manual Transcription API (Account Scoped)
- Implement account-scoped endpoint for on-demand transcription from audio message UI.

### TODO Checklist
- [ ] Add routes for `transcriptions#create` and `transcriptions#presets`.
- [ ] Create controller for transcription request lifecycle.
- [ ] Validate token presence, file constraints, and request parameters.
- [ ] Prefer `attachment_id` server-side fetch to avoid browser re-upload bottleneck.
- [ ] Keep multipart fallback path only if strictly necessary.
- [ ] Implement robust error mapping (invalid key, timeout, rate limit, format issues).
- [ ] Add safe caching in attachment metadata (merge, never overwrite full `meta`).
- [ ] Add explicit API timeouts (`open_timeout`, `read_timeout`) and map timeout errors to stable API responses.
- [ ] Ensure non-retryable errors are classified correctly (401/403/validation) vs retryable (timeout/network/429).

## Phase 4 - Conversation Audio UI Behavior
- Bring the proven UX behavior into current audio chip with minimal coupling.

### TODO Checklist
- [ ] Add transcribe action button to audio chip UI.
- [ ] Add loading/disabled/feedback states.
- [ ] Show token-missing dialog with action to profile settings.
- [ ] Render transcript with priority: local API response -> persisted attachment transcript.
- [ ] Keep existing playback, mute, speed, and download behavior unchanged.
- [ ] Prevent repeated click storms while request/job is already `processing`.
- [ ] Add/adjust frontend i18n strings (`en.json`) for all UI labels and errors.

## Phase 5 - Unify with Existing Automatic Transcription
- Preserve current enterprise async flow while eliminating metadata inconsistencies.

### TODO Checklist
- [ ] Ensure manual and automatic paths converge on one canonical metadata shape.
- [ ] Keep backward compatibility reading legacy `transcribed_text` during transition window.
- [ ] Avoid duplicate transcription work for same attachment (idempotency guard).
- [ ] Ensure message update event is emitted only after successful transcript persistence.
- [ ] Ensure search-related behavior remains compatible.
- [ ] Add optional migration/backfill strategy only if required for search consistency.

## Phase 6 - Reliability, Performance, and Security Hardening
- Make the implementation resilient under real traffic and failures.

### TODO Checklist
- [ ] Add explicit timeouts for external API requests.
- [ ] Add controlled retry/discard strategy for async jobs and bad requests.
- [ ] Enforce max audio size and allowed MIME/content validation.
- [ ] Add safe temporary file handling and cleanup.
- [ ] Add structured logs for transcription lifecycle and failure causes.
- [ ] Add basic observability counters (success/error/cache-hit/latency) if instrumentation hooks exist.
- [ ] Add feature kill switch (global) and account-level guard to disable transcription quickly.
- [ ] Validate no secret/token leakage in logs, traces, and error payloads.

## Phase 7 - Tests and Validation
- Validate behavior end-to-end and prevent regressions.

### TODO Checklist
- [ ] Backend request specs for transcription endpoint success/failure/cache.
- [ ] Backend service/controller specs for metadata persistence and error mapping.
- [ ] Job specs for async transcription behavior and retry/discard rules.
- [ ] Frontend tests for audio-chip transcribe flow and token-missing state.
- [ ] Add tests for idempotency behavior (parallel requests for same attachment).
- [ ] Add tests confirming `meta` merge does not remove unrelated keys.
- [ ] Manual smoke test on conversation UI with real audio attachment.
- [ ] Confirm no regressions in audio playback and existing message rendering.

## Phase 8 - Internal Review, Integration Branch, and Final Merge
- Perform final fork-internal rollout steps only after approval.

### TODO Checklist
- [ ] Open internal PR from feature branch (fork only, no upstream PR).
- [ ] Address review feedback and re-run validations.
- [ ] Create integration branch from latest fork `main`.
- [ ] Merge feature branch into integration branch and resolve conflicts.
- [ ] Run final lint/tests/smoke validation on integration branch.
- [ ] Merge integration branch into fork `main` after approval.

## Files Expected to Be Touched
- `app/controllers/api/v1/profiles_controller.rb`
- `app/views/api/v1/models/_user.json.jbuilder`
- `app/javascript/dashboard/routes/dashboard/settings/profile/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/profile/GroqToken.vue`
- `app/javascript/dashboard/components-next/message/chips/Audio.vue`
- `app/controllers/api/v1/accounts/transcriptions_controller.rb`
- `app/javascript/dashboard/api/transcription.js`
- `app/javascript/dashboard/composables/useTranscription.js`
- `config/routes.rb`
- `db/migrate/*_add_groq_token_to_users.rb`
- `enterprise/app/services/messages/audio_transcription_service.rb` (only if compatibility updates are required)
- `enterprise/app/jobs/messages/audio_transcription_job.rb` (only if reliability updates are required)
- `config/locales/en.yml`
- `app/javascript/dashboard/i18n/locale/en/*.json`

## Done Criteria
- Groq token can be configured in profile and is persisted per user.
- Audio message UI can trigger transcription on demand and display results reliably.
- Transcript persists and reappears after page refresh.
- Automatic transcription flow remains functional and compatible.
- Canonical metadata format is in use, with temporary compatibility for legacy data.
- Duplicate transcription requests are safely deduplicated per attachment.
- No secret/token appears in logs or API error payloads.
- No upstream PR is created; merge is completed internally in fork `main`.
