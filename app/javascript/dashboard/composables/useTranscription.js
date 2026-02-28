import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import transcriptionAPI from 'dashboard/api/transcription';

export const useTranscription = () => {
  const { t } = useI18n();
  const currentUser = useMapGetter('getCurrentUser');

  const isTranscribing = ref(false);
  const transcription = ref(null);
  const transcriptionError = ref(null);
  const isCached = ref(false);

  const hasGroqToken = () => {
    return currentUser.value?.has_groq_token === true;
  };

  const transcribe = async (attachment, options = {}) => {
    if (!hasGroqToken()) {
      transcriptionError.value = {
        type: 'token_missing',
        message: t('AUDIO.TOKEN_MISSING.MESSAGE'),
      };
      return { success: false, error: transcriptionError.value };
    }

    isTranscribing.value = true;
    transcriptionError.value = null;
    transcription.value = null;
    isCached.value = false;

    try {
      const formData = new FormData();

      // Prefer attachment_id to avoid browser download+upload
      if (attachment.id) {
        formData.append('attachment_id', attachment.id);
      } else if (attachment.dataUrl) {
        // Fallback: fetch and upload file
        const response = await fetch(attachment.dataUrl);
        const blob = await response.blob();
        const filename = attachment.file?.filename || 'audio.mp3';
        formData.append('file', blob, filename);
      } else {
        throw new Error('No attachment ID or data URL provided');
      }

      if (options.qualityPreset) {
        formData.append('quality_preset', options.qualityPreset);
      }

      if (options.model) {
        formData.append('model', options.model);
      }

      if (options.language) {
        formData.append('language', options.language);
      }

      if (options.forceRefresh) {
        formData.append('force_refresh', 'true');
      }

      const result = await transcriptionAPI.transcribe(formData);

      transcription.value = result.data.text;
      isCached.value = result.data.cached || false;

      useAlert(
        isCached.value
          ? t('AUDIO.TRANSCRIPTION.SUCCESS_CACHED')
          : t('AUDIO.TRANSCRIPTION.SUCCESS')
      );

      return {
        success: true,
        text: result.data.text,
        cached: result.data.cached,
        metadata: result.data.metadata,
      };
    } catch (error) {
      const errorData = error.response?.data || {};
      const status = error.response?.status;
      let errorMessage = errorData.message || t('AUDIO.TRANSCRIPTION.ERROR');

      if (status === 401 || status === 403) {
        errorMessage = t('AUDIO.API_ERROR.UNAUTHORIZED');
      }

      transcriptionError.value = {
        type: errorData.error_type || 'unknown',
        message: errorMessage,
        translationKey: errorData.translation_key,
        status,
      };

      useAlert(errorMessage);

      return {
        success: false,
        error: transcriptionError.value,
      };
    } finally {
      isTranscribing.value = false;
    }
  };

  const getPresets = async () => {
    try {
      const result = await transcriptionAPI.getPresets();
      return result.data;
    } catch (error) {
      useAlert(t('AUDIO.PRESETS.ERROR'));
      return {
        presets: ['voice', 'high_quality', 'small_size'],
        default_preset: 'voice',
      };
    }
  };

  const clearTranscription = () => {
    transcription.value = null;
    transcriptionError.value = null;
    isCached.value = false;
  };

  return {
    isTranscribing,
    transcription,
    transcriptionError,
    isCached,
    hasGroqToken,
    transcribe,
    getPresets,
    clearTranscription,
  };
};
