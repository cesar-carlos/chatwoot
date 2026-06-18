// FORK: extracted for merge-safe fork integration
import { computed, ref, unref } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useTranscription } from 'dashboard/composables/useTranscription';
import {
  readTranscriptText,
  readTranscriptState,
  readTranscriptError,
} from 'dashboard/composables/fork/useTranscriptText';

export const useAudioTranscription = attachmentSource => {
  const router = useRouter();
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

  const isProcessing = computed(() => {
    return isTranscribing.value || attachmentState.value === 'processing';
  });

  const persistedError = computed(() =>
    readTranscriptError(unref(attachmentSource))
  );

  const transcriptText = computed(() => {
    return transcription.value || readTranscriptText(unref(attachmentSource));
  });

  const displayError = computed(() => {
    return transcriptionError.value?.message || persistedError.value;
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
