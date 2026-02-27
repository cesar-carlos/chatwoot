# Audio Transcription (Groq) - Implementation Plan

## Objective
- Replicate the strong UX from the backup fork (audio player transcribe action + inline transcript + token setup screen).
- Adapt implementation to this fork's architecture with maximum merge safety and minimal upstream conflict risk.
- Keep delivery internal to this fork only (no upstream PR), with controlled branch integration into `main`.

## Scope Decisions
- Provider strategy: Groq token per user profile.
- Independence: Audio transcription is a standalone feature, NOT tied to Captain or any other feature.
- Fork strategy: minimal core edits, isolate behavior where possible, and mark divergent lines with `FORK:` tags.
- Delivery strategy: feature branch -> internal review -> integration branch from updated `main` -> merge to fork `main`.
- Security strategy: do not index `users.groq_token`, never log token values, and keep request parameter filtering for `groq_token`.
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
- [x] Expose `groq_token` in user serializer for profile field rehydration on reload.
- [x] Add `GroqToken` UI section in profile settings page.
- [x] Ensure token field remains masked and is never printed in client logs/errors.
- [x] Ensure backend filtered parameters include `groq_token` to prevent sensitive logging.
- [x] Add frontend i18n keys in `en.json`.
- [ ] Add backend i18n keys in `en.yml` (only if needed by API responses).

## Phase 3 - Manual Transcription API (Account Scoped)
- Implement account-scoped endpoint for on-demand transcription from audio message UI.

### TODO Checklist
- [x] Add routes for `transcriptions#create` and `transcriptions#presets`.
- [x] Create controller for transcription request lifecycle.
- [x] Validate token presence, file constraints, and request parameters.
- [x] Prefer `attachment_id` server-side fetch to avoid browser re-upload bottleneck.
- [x] Keep multipart fallback path only if strictly necessary.
- [x] Implement robust error mapping (invalid key, timeout, rate limit, format issues).
- [x] Add safe caching in attachment metadata (merge, never overwrite full `meta`).
- [x] Add explicit API timeouts (`open_timeout`, `read_timeout`) and map timeout errors to stable API responses.
- [x] Ensure non-retryable errors are classified correctly (401/403/validation) vs retryable (timeout/network/429).

## Phase 4 - Conversation Audio UI Behavior
- Bring the proven UX behavior into current audio chip with minimal coupling.

### TODO Checklist
- [x] Add transcribe action button to audio chip UI.
- [x] Add loading/disabled/feedback states.
- [x] Show token-missing dialog with action to profile settings.
- [x] Render transcript with priority: local API response -> persisted attachment transcript.
- [x] Keep existing playback, mute, speed, and download behavior unchanged.
- [x] Prevent repeated click storms while request/job is already `processing`.
- [x] Add/adjust frontend i18n strings (`en.json`) for all UI labels and errors.

## Phase 5 - Unify with Existing Automatic Transcription
- Preserve current enterprise async flow while eliminating metadata inconsistencies.

### TODO Checklist
- [x] Ensure manual and automatic paths converge on one canonical metadata shape.
- [x] Keep backward compatibility reading legacy `transcribed_text` during transition window.
- [x] Avoid duplicate transcription work for same attachment (idempotency guard).
- [x] Ensure message update event is emitted only after successful transcript persistence.
- [x] Ensure search-related behavior remains compatible.
- [ ] Add optional migration/backfill strategy only if required for search consistency.

## Phase 6 - Reliability, Performance, and Security Hardening
- Make the implementation resilient under real traffic and failures.

### TODO Checklist
- [x] Add explicit timeouts for external API requests.
- [x] Add controlled retry/discard strategy for async jobs and bad requests.
- [x] Enforce max audio size and allowed MIME/content validation.
- [x] Add safe temporary file handling and cleanup.
- [x] Add structured logs for transcription lifecycle and failure causes.
- [x] Add basic observability counters (success/error/cache-hit/latency) if instrumentation hooks exist.
- [x] Keep manual transcription independent from account-level toggle; user token is the access gate.
- [x] Validate no secret/token leakage in logs, traces, and error payloads.

## Phase 7 - Tests and Validation
- Validate behavior end-to-end and prevent regressions.

### TODO Checklist
- [ ] Backend request specs for transcription endpoint success/failure/cache.
- [ ] Backend service/controller specs for metadata persistence and error mapping.
- [ ] Job specs for async transcription behavior and retry/discard rules.
- [ ] Frontend tests for audio-chip transcribe flow and token-missing state.
- [ ] Add tests for idempotency behavior (parallel requests for same attachment).
- [ ] Add tests confirming `meta` merge does not remove unrelated keys.
- [x] Manual smoke test on conversation UI with real audio attachment.
- [ ] Confirm no regressions in audio playback and existing message rendering.
- [ ] Validate format matrix (direct send vs conversion):
  - [ ] `oga` / `x-oga` -> normalize to `ogg` and send direct
  - [ ] `opus` / `x-opus` -> send direct
  - [ ] `wav` / `mp3` / `m4a` / `webm` -> send direct
  - [ ] `aac` / `amr` -> convert to `mp3` (requires ffmpeg)
- [ ] Validate ffmpeg behavior:
  - [ ] conversion path works when ffmpeg is installed
  - [ ] user-facing error is clear when ffmpeg is missing

### Session Validation Status (2026-02-25)
- [x] Profile token UI rendered and accepted token save flow.
- [x] Profile token gate behavior validated (manual transcription allowed when user token exists).
- [x] Endpoint wiring validated (`POST /api/v1/accounts/:id/transcriptions` is reachable from audio chip).
- [x] `attachment_id` lookup path validated and fixed (`Attachment.find_by(id, account_id)`).
- [x] Error mapping path validated (422/500/403 surfaced correctly during troubleshooting).
- [x] Groq payload adjusted to match docs (`file`, `model`, `response_format`, `temperature`, optional `language`/`prompt`).
- [x] MIME normalization implemented for `audio/oga` and `audio/x-oga` to `audio/ogg`.
- [ ] Confirm successful end-to-end transcription after latest format/normalization fixes.
- [ ] Complete per-format success matrix (`oga`, `opus`, `wav`, `mp3`, `m4a`, `webm`, `aac`, `amr`).

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
- Audio format handling is explicit and validated (`oga/opus` direct support, `aac/amr` conversion path).

---

## Implementation Summary

### Completed Phases (0-6)

**Phase 0: Branch Setup** ✅
- Created feature branch `feat/audio-transcription-groq`
- Confirmed fork-internal workflow (no upstream PR)
- Defined integration strategy via merge branch

**Phase 1: Current State Analysis** ✅
- Mapped existing automatic transcription flow in `enterprise/`
- Documented metadata overwrite issue in legacy service
- Defined canonical metadata contract with backward compatibility
- Created detailed current state analysis document

**Phase 2: User Token Configuration** ✅
- Added `groq_token` column to users table (no index for security)
- Updated ProfilesController to permit token (with FORK marker)
- Exposed `groq_token` in user serializer to keep profile field populated after reload
- Created GroqToken.vue component for token management
- Integrated token section in profile settings UI
- Added i18n strings for all token-related UI
- Token automatically filtered from logs via existing parameter filter

**Phase 3: Manual Transcription API** ✅
- Created TranscriptionsController with create/presets endpoints
- Implemented server-side fetch via `attachment_id` (preferred path)
- Added multipart upload fallback for compatibility
- Added audio conversion pipeline (`AudioConverterService`) for unsupported formats before Groq call
- Implemented safe metadata merge (preserves existing keys)
- Added comprehensive error mapping for Groq API responses
- Set explicit timeouts (60s request, 10s open)
- Created frontend API client and useTranscription composable
- Added i18n strings for audio transcription errors
- Added routes with FORK marker

**Phase 4: Conversation UI Integration** ✅
- Added transcribe button with ear icon to Audio.vue chip
- Integrated useTranscription composable with loading states
- Added token-missing dialog with navigation to settings
- Display transcript with priority: API response > cached text
- Prevented duplicate clicks while transcribing
- Preserved existing playback controls
- All changes marked with FORK comments

**Phase 5: Automatic Flow Integration** ✅
- Updated AudioTranscriptionService to use safe meta merge
- Write to both `transcribed_text` (legacy) and `transcription` (canonical)
- Added idempotency check reading both metadata keys
- Removed Captain dependency (feature is now standalone)
- Removed usage limit checks (independent feature)
- Preserved existing message update and search reindex behavior
- All changes marked with FORK comments

**Phase 6: Reliability & Security** ✅
- Removed account-level guard for manual transcription (`audio_transcriptions`)
- Added structured logging for lifecycle events
- Added MIME/content handling strategy aligned with Groq support
- Improved file size validation with early return
- Token already filtered by existing parameter filter regex
- Temp file cleanup handled in controller with FileUtils.rm_f
- Added `AudioConverterService` for conditional conversion of unsupported formats
- Added MIME normalization (`audio/oga`/`audio/x-oga` -> `audio/ogg`) to avoid unnecessary conversion

**Hardening Pass (2026-02)** ✅
- UX: Profile screen now rehydrates token input from `groq_token` on reload
- Backend: `.oga` filename extension normalized to `.ogg` in `fetch_audio_from_attachment` (Groq validates by extension)
- Backend: Explicit `attachment_id` validation with 404 response when not found
- Backend: HTTP status mapping (401, 408, 429, 502, 503) per error type; `:unprocessable_content` where appropriate
- Frontend: Fixed `Audio.vue` props usage (`showTranscribedText`); multipart header removed (browser sets boundary)
- I18n: Added `AUDIO.API_ERROR.FFMPEG_MISSING` and `FILE_TOO_LARGE` keys (en, pt_BR)
- Metadata: Canonical metadata shape aligned across manual and automatic flows (`transcribed_at`, `metadata` structure)
- Setup: Added `ffmpeg` to `doc/scripts/setup-native-dev.sh`

**Phase 7: I18n** ✅
- All frontend strings in `en.json` and `pt_BR.json` (settings, conversation, errors)
- Complete translations for:
  - Profile settings (GROQ_TOKEN section)
  - Audio transcription UI (AUDIO section)
  - All error messages and feedback
- Backend error messages with translation keys

**Phase 8: Testing & Validation** 🔄 (in progress)
- [x] Migration executed successfully
- [x] RuboCop offenses fixed
- [x] ESLint auto-fixes applied
- [ ] Manual testing pending

### Key Technical Decisions

1. **Metadata Strategy**: Canonical `transcription` object + legacy `transcribed_text` for compatibility
2. **Idempotency**: Check both keys before processing to avoid duplicate work
3. **Security**: No index on token and filtered params enabled for `groq_token` to avoid secret leakage in logs
4. **Error Handling**: Comprehensive mapping with translation keys
5. **Performance**: Server-side file fetch to avoid browser re-upload
6. **Reliability**: Feature flag, timeouts, MIME validation, structured logging
7. **I18n**: Complete translations in English and Portuguese (pt-BR)
8. **Audio Compatibility**: direct send for Groq-supported formats, conversion only for unsupported ones

### Files Modified (with FORK markers)
- `app/controllers/api/v1/profiles_controller.rb`
- `app/views/api/v1/models/_user.json.jbuilder` (exposes `groq_token`)
- `app/javascript/dashboard/routes/dashboard/settings/profile/Index.vue`
- `app/javascript/dashboard/routes/dashboard/settings/profile/GroqToken.vue`
- `app/javascript/dashboard/components-next/message/chips/Audio.vue`
- `app/javascript/dashboard/api/transcription.js`
- `app/javascript/dashboard/composables/useTranscription.js`
- `config/routes.rb`
- `enterprise/app/services/messages/audio_transcription_service.rb`

### New Files Created
- `db/migrate/20260225131709_add_groq_token_to_users.rb`
- `app/javascript/dashboard/routes/dashboard/settings/profile/GroqToken.vue`
- `app/controllers/api/v1/accounts/transcriptions_controller.rb`
- `app/services/audio_converter_service.rb`
- `app/javascript/dashboard/api/transcription.js`
- `app/javascript/dashboard/composables/useTranscription.js`
- `doc/feature/audio-transcription/audio-transcription-groq-plan.md`
- `doc/feature/audio-transcription/audio-transcription-current-state.md`
- `doc/scripts/setup-native-dev.sh` (ffmpeg dependency)

### I18n Files Modified
- `app/javascript/dashboard/i18n/locale/en/settings.json` (GROQ_TOKEN section)
- `app/javascript/dashboard/i18n/locale/en/conversation.json` (AUDIO section)
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` (GROQ_TOKEN section)
- `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` (AUDIO section)

### Next Steps
1. Start development server and test token configuration
2. Test manual transcription with valid/invalid tokens
3. Test automatic transcription compatibility
4. Verify cache behavior and error messages
5. Create integration branch from latest `main`
6. Merge feature branch into integration branch
7. Final validation and merge to fork `main`
