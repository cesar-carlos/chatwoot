// FORK: extracted for merge-safe fork integration
import { computed, ref, unref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useTranscription } from 'dashboard/composables/useTranscription';
import {
  readTranscriptText,
  readTranscriptState,
  readTranscriptError,
} from 'dashboard/composables/fork/useTranscriptText';

export const useAudioTranscription = attachmentSource => {
  const router = useRouter();
  const { t } = useI18n();
  const {
    transcription,
    transcriptionError,
    hasGroqToken,
    transcribe,
  } = useTranscription();

  const localIsTranscribing = ref(false);

  const tokenMissingDialogRef = ref(null);
  const tokenInvalidDialogRef = ref(null);

  const attachmentState = computed(() =>
    readTranscriptState(unref(attachmentSource))
  );

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
    if (localIsTranscribing.value) return;

    const attachment = unref(attachmentSource);
    if (!hasGroqToken()) {
      tokenMissingDialogRef.value?.open();
      return;
    }

    localIsTranscribing.value = true;
    try {
      const result = await transcribe(attachment);

      if (
        !result.success &&
        result.error?.status &&
        (result.error.status === 401 || result.error.status === 403)
      ) {
        tokenInvalidDialogRef.value?.open();
      }
    } finally {
      localIsTranscribing.value = false;
    }
  };

  const goToSettings = () => {
    tokenMissingDialogRef.value?.close();
    tokenInvalidDialogRef.value?.close();
    router.push({ name: 'profile_settings_index' });
  };

  return {
    isTranscribing: localIsTranscribing,
    transcriptText,
    transcriptState: attachmentState,
    displayError,
    showTranscribeButton: true,
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
