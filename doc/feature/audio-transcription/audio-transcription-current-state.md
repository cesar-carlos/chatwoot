# Audio Transcription - Current State

> **Status**: Implementation complete with mutual exclusion between automatic (OpenAI) and manual (Groq) modes.

## Two Transcription Modes (Mutually Exclusive)

| Mode | Trigger | Provider | Gate |
|------|---------|----------|------|
| **Automatic (original)** | On audio upload | OpenAI `gpt-4o-mini-transcribe` | `account.settings.audio_transcriptions == true` |
| **Manual (fork Groq)** | User clicks transcribe button | Groq `whisper-large-v3-turbo` | `users.groq_token` present AND `audio_transcriptions == false` |

When `account.audio_transcriptions` is enabled, the fork Groq manual path is **disabled** (backend 422 + hidden UI button).

## Automatic Transcription Flow (Enterprise)

**Service**: `enterprise/app/services/messages/audio_transcription_service.rb`
- Extends `Llm::LegacyBaseOpenAiService`
- Model: `gpt-4o-mini-transcribe` (`TRANSCRIPTION_MODEL` constant)
- Gated by `account.audio_transcriptions` (standalone, not tied to Captain)
- Safe `meta` merge preserving other keys
- Writes canonical `meta['transcription']` + legacy `meta['transcribed_text']`
- Emits `message.send_update_event` and reindexes when advanced search is enabled

**Job**: `enterprise/app/jobs/messages/audio_transcription_job.rb`
- Queue: `:low`
- Discards on `Faraday::BadRequestError`
- Retries on `ActiveStorage::FileNotFoundError` (3 attempts, 2s wait)

**Trigger**: `enterprise/app/models/enterprise/concerns/attachment.rb`
- `after_create_commit :enqueue_audio_transcription`
- Only for audio attachments

## Manual Transcription Flow (Fork / Groq)

**Controller**: `custom/app/controllers/api/v1/accounts/transcriptions_controller.rb`
- Delegates to `Custom::Transcription::Orchestrator`
- Blocks when `account.audio_transcriptions` is enabled
- Cache hit only when `transcription.state == 'success'`
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
- `app/javascript/dashboard/composables/fork/useAudioTranscription.js` — hides button when automatic mode active
- `app/javascript/dashboard/components/fork/AudioTranscriptionFork.vue` — button, dialogs
- `app/javascript/dashboard/components-next/message/chips/Audio.vue` — audio chip integration

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
    'provider' => 'groq',  # groq|openai
    'model' => 'whisper-large-v3-turbo',
    'transcribed_at' => 1234567890,
    'metadata' => {}
  }
}
```

## Security

- `groq_token` is **not** returned in GET user API responses
- `has_groq_token` boolean exposed instead
- Profile updates use JSON PUT for scalar fields (including `groq_token`); blank token on partial update does not clear saved token
- `groq_token` encrypted at rest via Active Record Encryption (`encrypts :groq_token`)
- Profile UI shows "Token configured" placeholder when token exists but value is not returned
- `groq_token` filtered from logs via `filter_parameter_logging.rb`
- Manual transcription requires inbox access (`ConversationPolicy#show?`)

## Enabling Modes

- **Automatic**: `account.audio_transcriptions = true` (see `doc/scripts/enable-audio-transcription.rb`)
- **Manual Groq**: Settings → Profile → Groq API Token (per user)

See `enable-audio-transcriptions.md` for operator instructions.
