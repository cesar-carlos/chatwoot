import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  ATTACHMENT_TYPES,
  VOICE_CALL_STATUS,
} from 'dashboard/components-next/message/constants';

export function shouldShowVoiceCallRecording({
  provider,
  callStatus,
  recordingUrl,
  callRecordingEnabled,
}) {
  if (provider !== VOICE_CALL_PROVIDERS.WAVOIP) return true;
  if (callRecordingEnabled === false) return false;
  if (callStatus !== VOICE_CALL_STATUS.COMPLETED) return false;
  return Boolean(recordingUrl);
}

const RECORDING_PROCESSING_WINDOW_MS = 10 * 60 * 1000;

export function shouldShowRecordingProcessing({
  provider,
  callStatus,
  recordingUrl,
  callRecordingEnabled,
  completedAtMs,
}) {
  if (provider !== VOICE_CALL_PROVIDERS.WAVOIP) return false;
  if (callRecordingEnabled === false) return false;
  if (callStatus !== VOICE_CALL_STATUS.COMPLETED) return false;
  if (recordingUrl) return false;

  if (!completedAtMs) return true;

  return Date.now() - completedAtMs < RECORDING_PROCESSING_WINDOW_MS;
}

export function inferAudioExtension(url) {
  const match = url?.match(/\.([a-z0-9]+)(?:\?|#|$)/i);
  return match?.[1]?.toLowerCase() || 'ogg';
}

export function resolveVoiceCallRecordingUrl({
  audioAttachment,
  call,
  contentAttributes,
}) {
  if (audioAttachment) return audioAttachment;

  const url =
    call?.recordingUrl ||
    contentAttributes?.data?.recording_url ||
    contentAttributes?.data?.record_url;

  if (!url) return null;

  return {
    dataUrl: url,
    fileType: ATTACHMENT_TYPES.AUDIO,
    extension: inferAudioExtension(url),
    transcribedText: call?.transcript || '',
  };
}
