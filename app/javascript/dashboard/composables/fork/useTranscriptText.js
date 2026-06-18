// FORK: unified transcript text reader for attachment metadata
import { computed, unref } from 'vue';

export const readTranscriptText = attachment => {
  if (!attachment) return '';

  if (attachment.transcription?.text) {
    return attachment.transcription.text;
  }

  return attachment.transcribedText || attachment.transcribed_text || '';
};

export const readTranscriptState = attachment => {
  if (!attachment) return null;

  const state =
    attachment.transcriptionState ||
    attachment.transcription?.state ||
    attachment.transcription_state;

  if (state) return state;
  if (readTranscriptText(attachment)) return 'success';

  return null;
};

export const readTranscriptError = attachment => {
  if (!attachment) return null;

  return (
    attachment.transcriptionError ||
    attachment.transcription?.error ||
    attachment.transcription_error ||
    null
  );
};

export const readTranscriptionStartedAt = attachment => {
  if (!attachment) return null;

  return (
    attachment.transcriptionStartedAt ||
    attachment.transcription?.started_at ||
    attachment.transcription_started_at ||
    null
  );
};

export const useTranscriptText = attachmentSource => {
  const transcriptText = computed(() =>
    readTranscriptText(unref(attachmentSource))
  );
  const transcriptState = computed(() =>
    readTranscriptState(unref(attachmentSource))
  );
  const transcriptError = computed(() =>
    readTranscriptError(unref(attachmentSource))
  );

  return {
    transcriptText,
    transcriptState,
    transcriptError,
  };
};
