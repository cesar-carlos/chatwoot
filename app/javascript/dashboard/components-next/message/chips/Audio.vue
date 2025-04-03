<script setup>
import { computed, onMounted, useTemplateRef, ref } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { timeStampAppendedURL } from 'dashboard/helper/URLHelper';
import { downloadFile } from '@chatwoot/utils';
import axios from 'axios';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const { attachment } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});

const { t: $t } = useI18n();

defineOptions({
  inheritAttrs: false,
});

const currentUser = useMapGetter('getCurrentUser');
const hasGroqToken = computed(() => currentUser.value?.groq_token?.length > 0);

const timeStampURL = computed(() => {
  return timeStampAppendedURL(attachment.dataUrl);
});

const audioPlayer = useTemplateRef('audioPlayer');

const isPlaying = ref(false);
const isMuted = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const playbackSpeed = ref(2);
const showTranscription = ref(false);
const isTranscribing = ref(false);
const transcriptionText = ref('');
const showGroqAlert = ref(false);
const transcriptionError = ref('');

const onLoadedMetadata = () => {
  duration.value = audioPlayer.value?.duration;
};

const playbackSpeedLabel = computed(() => {
  return `${playbackSpeed.value}x`;
});

// There maybe a chance that the audioPlayer ref is not available
// When the onLoadMetadata is called, so we need to set the duration
// value when the component is mounted
onMounted(() => {
  duration.value = audioPlayer.value?.duration;
  audioPlayer.value.playbackRate = playbackSpeed.value;

  // Carrega a transcrição existente se houver
  if (attachment.meta?.transcription) {
    transcriptionText.value = attachment.meta.transcription;
    showTranscription.value = true;
  }
});

const formatTime = time => {
  if (!time || Number.isNaN(time)) return '00:00';
  const minutes = Math.floor(time / 60);
  const seconds = Math.floor(time % 60);
  return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
};

const toggleMute = () => {
  audioPlayer.value.muted = !audioPlayer.value.muted;
  isMuted.value = audioPlayer.value.muted;
};

const onTimeUpdate = () => {
  currentTime.value = audioPlayer.value?.currentTime;
};

const seek = event => {
  const time = Number(event.target.value);
  audioPlayer.value.currentTime = time;
  currentTime.value = time;
};

const playOrPause = () => {
  if (isPlaying.value) {
    audioPlayer.value.pause();
    isPlaying.value = false;
  } else {
    audioPlayer.value.play();
    isPlaying.value = true;
  }
};

const onEnd = () => {
  isPlaying.value = false;
  currentTime.value = 0;
  playbackSpeed.value = 2;
  audioPlayer.value.playbackRate = 2;
};

const changePlaybackSpeed = () => {
  const speeds = [1, 1.5, 2, 3];
  const currentIndex = speeds.indexOf(playbackSpeed.value);
  const nextIndex = (currentIndex + 1) % speeds.length;
  playbackSpeed.value = speeds[nextIndex];
  audioPlayer.value.playbackRate = playbackSpeed.value;
};

const downloadAudio = async () => {
  const { fileType, dataUrl, extension } = attachment;
  downloadFile({ url: dataUrl, type: fileType, extension });
};

const closeGroqAlert = () => {
  showGroqAlert.value = false;
  transcriptionError.value = '';
};

const handleTranscribeAudio = async () => {
  if (isTranscribing.value) return;

  if (!hasGroqToken.value) {
    showGroqAlert.value = true;
    return;
  }

  try {
    isTranscribing.value = true;
    transcriptionText.value = $t('CONVERSATION.TRANSCRIBING');
    showTranscription.value = true;

    const response = await axios.post(
      `/api/v1/attachments/${attachment.id}/transcribe`
    );

    if (response.data.success) {
      transcriptionText.value = response.data.transcription;
    } else {
      throw new Error(response.data.error);
    }
  } catch (error) {
    transcriptionError.value =
      error.response?.data?.error ||
      'Erro ao transcrever o áudio. Por favor, tente novamente.';
    showGroqAlert.value = true;
    transcriptionText.value = '';
  } finally {
    isTranscribing.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col items-end my-4">
    <div class="w-[280px]">
      <div class="flex items-center">
        <button
          class="p-1 rounded-full hover:bg-n-alpha-1 transition-colors"
          :title="$t('CONVERSATION.TRANSCRIBE_AUDIO')"
          @click="handleTranscribeAudio"
        >
          <Icon icon="i-lucide-ear" class="size-3 text-n-slate-11" />
        </button>
        <audio
          ref="audioPlayer"
          :src="timeStampURL"
          class="hidden"
          @loadedmetadata="onLoadedMetadata"
          @timeupdate="onTimeUpdate"
          @ended="onEnd"
        />
        <div class="flex items-center flex-1">
          <button
            class="p-1 rounded-full hover:bg-n-alpha-1 transition-colors"
            @click="playOrPause"
          >
            <Icon
              :icon="isPlaying ? 'i-lucide-pause' : 'i-lucide-play'"
              class="size-3 text-n-slate-11"
            />
          </button>
          <div class="flex-1 min-w-[200px] flex flex-col justify-center">
            <input
              type="range"
              :value="currentTime"
              :max="duration"
              class="w-full"
              @input="seek"
            />
            <div class="flex justify-between text-xs text-n-slate-11">
              <span>{{ formatTime(currentTime) }}</span>
              <span>{{ formatTime(duration) }}</span>
            </div>
          </div>
          <button
            class="p-1 rounded-full hover:bg-n-alpha-1 transition-colors"
            @click="toggleMute"
          >
            <Icon
              :icon="isMuted ? 'i-lucide-volume-x' : 'i-lucide-volume-2'"
              class="size-3 text-n-slate-11"
            />
          </button>
          <button
            class="p-1 rounded-full hover:bg-n-alpha-1 transition-colors"
            @click="changePlaybackSpeed"
          >
            <span class="text-xs text-n-slate-11">{{
              playbackSpeedLabel
            }}</span>
          </button>
          <button
            class="p-1 rounded-full hover:bg-n-alpha-1 transition-colors"
            @click="downloadAudio"
          >
            <Icon icon="i-lucide-download" class="size-3 text-n-slate-11" />
          </button>
        </div>
      </div>
    </div>
    <div
      v-if="showTranscription"
      class="p-2 bg-n-alpha-1 rounded-lg text-sm text-n-slate-11 max-w-[800px] mt-1 flex items-start gap-2"
    >
      <Icon icon="i-lucide-lock" class="size-4 text-n-slate-11 mt-0.5" />
      <span>{{ transcriptionText }}</span>
    </div>

    <!-- Alerta de Token GROQ ou Erro de Transcrição -->
    <div
      v-if="showGroqAlert"
      class="fixed inset-0 flex items-center justify-center z-50 bg-black bg-opacity-50"
    >
      <div
        class="bg-white dark:bg-slate-800 rounded-lg p-6 shadow-lg max-w-md w-full mx-4 relative"
      >
        <div class="mb-4">
          <h3 class="text-lg font-semibold text-slate-800 dark:text-slate-200">
            {{ $t('CONVERSATION.TRANSCRIPTION_ERROR.TITLE') }}
          </h3>
        </div>
        <div class="mb-6">
          <p class="text-slate-700 dark:text-slate-300">
            {{ transcriptionError || $t('CONVERSATION.GROQ_TOKEN_MISSING') }}
          </p>
        </div>
        <div class="flex justify-end">
          <button
            class="px-4 py-2 bg-woot-500 text-white rounded hover:bg-woot-600 transition-colors"
            @click="closeGroqAlert"
          >
            {{ $t('CONVERSATION.VOICE_CALL_MODAL.ERROR.CLOSE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
