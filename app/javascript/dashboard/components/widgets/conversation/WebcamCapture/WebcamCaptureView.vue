<script setup>
import { ref, computed, watch, onBeforeUnmount, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  stream: {
    type: Object,
    default: null,
  },
  isStarting: {
    type: Boolean,
    default: false,
  },
  isVideoReady: {
    type: Boolean,
    default: false,
  },
  error: {
    type: String,
    default: null,
  },
  capturedPreviewUrl: {
    type: String,
    default: null,
  },
  hasCapturedFile: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['capture', 'retake', 'retry', 'videoReady']);

const { t } = useI18n();
const videoEl = ref(null);

const errorMessage = computed(() => {
  if (!props.error) return '';
  return t(`CONVERSATION.WEBCAM_CAPTURE.ERROR.${props.error}`);
});

const bindStream = async mediaStream => {
  await nextTick();
  if (!videoEl.value) return;

  videoEl.value.srcObject = mediaStream || null;
  if (mediaStream) {
    try {
      await videoEl.value.play();
    } catch {
      // Autoplay can fail until metadata; loadedmetadata handler covers ready state.
    }
  }
};

watch(
  () => props.stream,
  mediaStream => {
    bindStream(mediaStream);
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  if (videoEl.value) {
    videoEl.value.srcObject = null;
  }
});

const onLoadedMetadata = () => {
  const ready = Boolean(videoEl.value?.videoWidth);
  emit('videoReady', ready);
};

const handleCapture = () => {
  emit('capture', videoEl.value);
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div
      class="relative flex items-center justify-center w-full overflow-hidden rounded-lg aspect-video bg-n-solid-3"
    >
      <div
        v-if="isStarting && !stream && !hasCapturedFile && !error"
        class="flex flex-col items-center gap-2 text-n-slate-11"
      >
        <Spinner />
        <span class="text-sm">
          {{ t('CONVERSATION.WEBCAM_CAPTURE.MODAL.STARTING') }}
        </span>
      </div>

      <p
        v-else-if="error && !hasCapturedFile"
        class="px-4 text-sm text-center text-n-ruby-11"
      >
        {{ errorMessage }}
      </p>

      <img
        v-else-if="hasCapturedFile && capturedPreviewUrl"
        :src="capturedPreviewUrl"
        alt=""
        class="object-cover w-full h-full"
      />

      <video
        v-show="Boolean(stream) && !hasCapturedFile && !error"
        ref="videoEl"
        autoplay
        playsinline
        muted
        class="object-cover w-full h-full"
        @loadedmetadata="onLoadedMetadata"
      />
    </div>

    <div class="flex justify-center gap-2">
      <NextButton
        v-if="error && !hasCapturedFile"
        :label="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.RETRY')"
        color="blue"
        sm
        :disabled="isStarting"
        @click="emit('retry')"
      />
      <NextButton
        v-else-if="!hasCapturedFile"
        :label="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.CAPTURE')"
        color="blue"
        sm
        :disabled="!isVideoReady || isStarting || !stream"
        @click="handleCapture"
      />
      <NextButton
        v-else
        :label="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.RETAKE')"
        slate
        faded
        sm
        :disabled="isStarting"
        @click="emit('retake')"
      />
    </div>
  </div>
</template>
