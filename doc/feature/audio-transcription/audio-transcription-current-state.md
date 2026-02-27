# Audio Transcription - Current State Analysis

> **Status**: Implementation complete. This document describes the baseline state before changes and the decisions made. See `audio-transcription-groq-plan.md` for full implementation details.

## Existing Infrastructure

### Automatic Transcription Flow (Enterprise)

**Service**: `enterprise/app/services/messages/audio_transcription_service.rb`
- Extends `Llm::LegacyBaseOpenAiService`
- Uses OpenAI Whisper (`whisper-1`)
- Reads/writes `meta['transcribed_text']` (legacy key)
- **Issue**: Overwrites entire `meta` object (line 92)
- Does not require `account.audio_transcriptions` for manual profile-token flow
- Checks Captain usage limits

**Job**: `enterprise/app/jobs/messages/audio_transcription_job.rb`
- Queue: `:low`
- Discards on `Faraday::BadRequestError`
- Retries on `ActiveStorage::FileNotFoundError` (3 attempts, 2s wait)

**Trigger**: `enterprise/app/models/enterprise/concerns/attachment.rb`
- `after_create_commit :enqueue_audio_transcription`
- Only for audio attachments

### Data Model

**Attachment** (`app/models/attachment.rb`)
- Has `meta` jsonb column (no GIN index visible in schema comment)
- `audio_metadata` method exposes `transcribed_text` from meta
- Includes enterprise concern via `Attachment.include_mod_with('Concerns::Attachment')`

### Current Issues Identified

1. **Metadata overwrite risk** (line 92 in service):
   ```ruby
   attachment.update!(meta: { transcribed_text: transcribed_text })
   ```
   This replaces the entire `meta` hash, losing other keys.

2. **No idempotency guard**: Multiple transcription requests for same attachment will re-process.

3. **No explicit states**: Can't distinguish `pending` vs `processing` vs `error`.

4. **No manual transcription path**: Only automatic on upload.

5. **OpenAI only**: No Groq support or per-user token configuration.

## Required Changes Summary

> Historical note: the list below reflects the original baseline. Some items are now implemented and should be read as completed deltas.

### Must Add
- User `groq_token` field (no index)
- Manual transcription endpoint (`TranscriptionsController`)
- Frontend UI for token configuration
- Frontend UI for manual transcribe action
- Idempotency mechanism per attachment
- Safe meta merge (preserve existing keys)
- Explicit transcription states

### Must Preserve
- Existing automatic flow for backward compatibility
- `transcribed_text` reading for legacy data
- Message update events
- Search reindexing behavior
- ~~Captain usage limit checks~~ (removed: feature is standalone per scope decision)

### Migration Strategy
- Add new canonical metadata structure alongside legacy
- Read from both during transition
- Write to new structure going forward
- Keep `transcribed_text` populated for compatibility window

## Metadata Contract (Proposed)

### Legacy (current)
```ruby
meta: {
  'transcribed_text' => 'text here'
}
```

### Canonical (new)
```ruby
meta: {
  'transcribed_text' => 'text here',  # kept for compatibility
  'transcription' => {
    'text' => 'text here',
    'state' => 'success',  # pending|processing|success|error
    'provider' => 'groq',  # groq|openai
    'model' => 'whisper-large-v3-turbo',
    'transcribed_at' => 1234567890,
    'error' => nil,  # error message if state=error
    'metadata' => {}  # provider-specific metadata
  }
}
```

## Files Requiring FORK Markers

These core files will need minimal edits with `# FORK:` or `// FORK:` markers:

- `app/controllers/api/v1/profiles_controller.rb` (permit groq_token)
- `app/views/api/v1/models/_user.json.jbuilder` (expose groq_token)
- `app/javascript/dashboard/routes/dashboard/settings/profile/Index.vue` (add token section)
- `app/javascript/dashboard/components-next/message/chips/Audio.vue` (add transcribe button)
- `config/routes.rb` (add transcriptions routes)
- `enterprise/app/services/messages/audio_transcription_service.rb` (safe meta merge)

## New Files (No Upstream Conflict)

- `db/migrate/*_add_groq_token_to_users.rb`
- `app/javascript/dashboard/routes/dashboard/settings/profile/GroqToken.vue`
- `app/controllers/api/v1/accounts/transcriptions_controller.rb`

## Current Effective Rules (implemented)

- Manual transcription access is gated by user token presence (`users.groq_token`).
- Account-level `audio_transcriptions` is not used as a blocker for manual transcription.
- Profile payload now carries `groq_token` and profile UI reload shows masked token value.
- `app/javascript/dashboard/api/transcription.js`
- `app/javascript/dashboard/composables/useTranscription.js`
- I18n keys in `config/locales/en.yml` and `app/javascript/dashboard/i18n/locale/en/*.json`
