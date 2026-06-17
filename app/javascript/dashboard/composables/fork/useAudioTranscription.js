// FORK: extracted for merge-safe fork integration
import { computed, ref, unref } from 'vue';
import { useRouter } from 'vue-router';
import { useTranscription } from 'dashboard/composables/useTranscription';

export const useAudioTranscription = attachmentSource => {
  const router = useRouter();
  const { isTranscribing, transcription, hasGroqToken, transcribe } =
    useTranscription();

  const tokenMissingDialogRef = ref(null);
  const tokenInvalidDialogRef = ref(null);

  const transcriptText = computed(() => {
    const attachment = unref(attachmentSource);
    return transcription.value || attachment?.transcribedText || '';
  });

  const handleTranscribe = async () => {
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
    isTranscribing,
    transcriptText,
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
