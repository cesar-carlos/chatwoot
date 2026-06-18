// FORK: extracted for merge-safe fork integration
import { computed, ref, unref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useTranscription } from 'dashboard/composables/useTranscription';
import {
  readTranscriptText,
  readTranscriptState,
  readTranscriptError,
  readTranscriptionStartedAt,
} from 'dashboard/composables/fork/useTranscriptText';

const STALE_PROCESSING_MS = 120 * 1000;

const isStaleProcessing = startedAt => {
  if (!startedAt) return true;

  return Date.now() - startedAt * 1000 > STALE_PROCESSING_MS;
};

export const useAudioTranscription = attachmentSource => {
  const router = useRouter();
  const { t } = useI18n();
  const { currentAccount } = useAccount();
  const {
    isTranscribing,
    transcription,
    transcriptionError,
    hasGroqToken,
    transcribe,
  } = useTranscription();

  const tokenMissingDialogRef = ref(null);
  const tokenInvalidDialogRef = ref(null);

  const isAutomaticTranscriptionEnabled = computed(() => {
    return !!currentAccount.value?.settings?.audio_transcriptions;
  });

  const showTranscribeButton = computed(() => {
    return !isAutomaticTranscriptionEnabled.value;
  });

  const attachmentState = computed(() =>
    readTranscriptState(unref(attachmentSource))
  );

  const transcriptionStartedAt = computed(() =>
    readTranscriptionStartedAt(unref(attachmentSource))
  );

  const isAttachmentProcessingActive = computed(() => {
    if (attachmentState.value !== 'processing') return false;

    return !isStaleProcessing(transcriptionStartedAt.value);
  });

  const isProcessing = computed(() => {
    return isTranscribing.value || isAttachmentProcessingActive.value;
  });

  const persistedError = computed(() =>
    readTranscriptError(unref(attachmentSource))
  );

  const transcriptText = computed(() => {
    return transcription.value || readTranscriptText(unref(attachmentSource));
  });

  const displayError = computed(() => {
    if (transcriptionError.value?.message) {
      return transcriptionError.value.message;
    }

    if (attachmentState.value === 'error' && persistedError.value) {
      return t('AUDIO.TRANSCRIPTION.ERROR_STATE', {
        error: persistedError.value,
      });
    }

    return persistedError.value;
  });

  const handleTranscribe = async () => {
    if (isAutomaticTranscriptionEnabled.value || isProcessing.value) return;

    const attachment = unref(attachmentSource);
    if (!hasGroqToken()) {
      tokenMissingDialogRef.value?.open();
      return;
    }

    const result = await transcribe(attachment);

    if (
      !result.success &&
      result.error?.status &&
      (result.error.status === 401 || result.error.status === 403)
    ) {
      tokenInvalidDialogRef.value?.open();
    }
  };

  const goToSettings = () => {
    tokenMissingDialogRef.value?.close();
    tokenInvalidDialogRef.value?.close();
    router.push({ name: 'profile_settings_index' });
  };

  return {
    isTranscribing: isProcessing,
    transcriptText,
    transcriptState: attachmentState,
    displayError,
    showTranscribeButton,
    setTokenMissingDialog: el => {
      tokenMissingDialogRef.value = el;
    },
    setTokenInvalidDialog: el => {
      tokenInvalidDialogRef.value = el;
    },
    handleTranscribe,
    goToSettings,
  };
};
