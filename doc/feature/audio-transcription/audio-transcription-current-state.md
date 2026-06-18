# Audio Transcription - Current State

> **Status**: Manual-only mode. Transcription happens only when a user clicks the ear icon.

## Transcription Mode

| Trigger | Provider | Gate |
|---------|----------|------|
| User clicks ear icon | Groq `whisper-large-v3-turbo` | `users.groq_token` present |

Automatic transcription on upload (OpenAI via `account.audio_transcriptions`) is **disabled** in this fork. The account settings toggle is hidden.

## Manual Transcription Flow (Groq)

**Controller**: `custom/app/controllers/api/v1/accounts/transcriptions_controller.rb`
- Delegates to `Custom::Transcription::Orchestrator`
- **Idempotency**: checks `attachment.meta` in the database before any Groq API call; returns cached text when `state == success` (unless `force_refresh=true`)
- Sets `processing` before Groq call; `error` with message on failure
- Redis lock (~120s) per attachment; 409 only for actively in-flight (lock held + recent `started_at`)
- Stale `processing` state (older than TTL) is auto-recovered
- `force_refresh=true` bypasses cache and processing/error states
- Inbox authorization via `ConversationPolicy#show?`; 403 when unauthorized
- File size validation via `attachment.file.blob.byte_size` (25MB max)
- Rate limit: 10/min per user (controller + Rack::Attack)
- Structured lifecycle logs: start, cache_hit, success, error (with duration_ms)
- After save: `message.reload.send_update_event` + conditional reindex

**Services** (custom overlay):
- `custom/app/services/custom/transcription/orchestrator.rb` — lock, cache, processing lifecycle, provider call, broadcast
- `custom/app/services/custom/transcription/groq_provider.rb` — provider strategy
- `custom/app/services/custom/transcription_metadata.rb` — unified read/write + stale processing recovery
- `custom/app/services/custom/groq/audio_transcription_service.rb` — Groq API calls
- `custom/app/services/custom/audio_converter_service.rb` — FFmpeg conversion only for unsupported formats (aac, amr, etc.)

**Frontend**:
- `app/javascript/dashboard/composables/fork/useAudioTranscription.js` — ear button always visible; processing UI only during active user request
- `app/javascript/dashboard/components/fork/AudioTranscriptionFork.vue` — button, dialogs
- `app/javascript/dashboard/components-next/message/chips/Audio.vue` — audio chip integration

**Disabled automatic path**:
- `enterprise/app/models/enterprise/concerns/attachment.rb` — `enqueue_audio_transcription` returns early (FORK); no `AudioTranscriptionJob` on upload

## Data Model

**Attachment** (`app/models/attachment.rb`)
- `meta` jsonb column
- `audio_metadata` exposes `transcribedText`, `transcription_state`, `transcription_error`, `transcription_started_at` from meta

### Canonical metadata shape

```ruby
meta: {
  'transcribed_text' => 'text here',  # legacy compatibility
  'transcription' => {
    'text' => 'text here',
    'state' => 'success',  # pending|processing|success|error
    'provider' => 'groq',
    'model' => 'whisper-large-v3-turbo',
    'transcribed_at' => 1234567890,
    'metadata' => {}
  }
}
```

## Security

- `groq_token` is **not** returned in GET user API responses
- `has_groq_token` boolean exposed on profile GET and `/auth/validate_token` (page refresh)
- Profile updates use JSON PUT for scalar fields (including `groq_token`); blank token on partial update does not clear saved token
- `groq_token` encrypted at rest via Active Record Encryption (`encrypts :groq_token`)
- Profile UI shows "Token configured" placeholder when token exists but value is not returned
- `groq_token` filtered from logs via `filter_parameter_logging.rb`
- Manual transcription requires inbox access (`ConversationPolicy#show?`)

## Setup

1. Each agent adds a Groq API token in **Settings → Profile**.
2. In a conversation, click the ear icon on an audio message to transcribe.

See `enable-audio-transcriptions.md` for operator instructions.
