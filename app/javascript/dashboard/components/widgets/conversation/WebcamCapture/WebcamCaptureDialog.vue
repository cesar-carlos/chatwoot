<script setup>
import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WebcamCaptureView from './WebcamCaptureView.vue';
import { useWebcamCapture } from 'dashboard/composables/useWebcamCapture';

const emit = defineEmits(['capture', 'devices-granted']);

const { t } = useI18n();
const dialogRef = ref(null);

const {
  stream,
  isStarting,
  isVideoReady,
  error,
  capturedFile,
  capturedPreviewUrl,
  startStream,
  markVideoReady,
  capturePhoto,
  retake,
  reset,
} = useWebcamCapture();

const disableConfirmButton = computed(() => !capturedFile.value);

const startCamera = async () => {
  const mediaStream = await startStream();
  if (mediaStream) {
    emit('devices-granted');
  }
};

const handleOpen = async () => {
  reset();
  dialogRef.value?.open();
  // Wait for Dialog slot (v-if="isOpen") so <video> exists before binding.
  await nextTick();
  await startCamera();
};

const handleClose = () => {
  reset();
};

const handleConfirm = () => {
  const file = capturedFile.value;
  if (!file) return;
  emit('capture', file);
  dialogRef.value?.close();
};

const handleCapture = async videoEl => {
  await capturePhoto(videoEl);
};

const handleRetake = async () => {
  await retake();
};

const handleRetry = async () => {
  await startCamera();
};

const handleVideoReady = ready => {
  markVideoReady(ready);
};

watch(stream, mediaStream => {
  if (!mediaStream) {
    markVideoReady(false);
  }
});

const open = () => {
  handleOpen();
};

const close = () => {
  dialogRef.value?.close();
  reset();
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="lg"
    overflow-y-auto
    :title="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.TITLE')"
    :description="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.CONFIRM')"
    :cancel-button-label="t('CONVERSATION.WEBCAM_CAPTURE.MODAL.CANCEL')"
    :disable-confirm-button="disableConfirmButton"
    @confirm="handleConfirm"
    @close="handleClose"
  >
    <WebcamCaptureView
      :stream="stream"
      :is-starting="isStarting"
      :is-video-ready="isVideoReady"
      :error="error"
      :captured-preview-url="capturedPreviewUrl"
      :has-captured-file="Boolean(capturedFile)"
      @capture="handleCapture"
      @retake="handleRetake"
      @retry="handleRetry"
      @video-ready="handleVideoReady"
    />
  </Dialog>
</template>
