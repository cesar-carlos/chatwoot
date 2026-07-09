import { ref, onUnmounted } from 'vue';
import getUuid from 'widget/helpers/uuid';

const VIDEO_CONSTRAINTS = {
  audio: false,
  video: {
    facingMode: { ideal: 'user' },
    width: { ideal: 1280 },
    height: { ideal: 720 },
  },
};

/**
 * Manages webcam MediaStream lifecycle and JPEG frame capture.
 */
export const useWebcamCapture = () => {
  const stream = ref(null);
  const isStarting = ref(false);
  const isVideoReady = ref(false);
  const error = ref(null);
  const capturedFile = ref(null);
  const capturedPreviewUrl = ref(null);

  // Invalidates in-flight getUserMedia when the dialog closes mid-request.
  let startGeneration = 0;

  const clearCapturedPreview = () => {
    if (capturedPreviewUrl.value) {
      URL.revokeObjectURL(capturedPreviewUrl.value);
      capturedPreviewUrl.value = null;
    }
    capturedFile.value = null;
  };

  const stopStream = () => {
    startGeneration += 1;
    stream.value?.getTracks()?.forEach(track => track.stop());
    stream.value = null;
    isVideoReady.value = false;
    isStarting.value = false;
  };

  const reset = () => {
    stopStream();
    clearCapturedPreview();
    error.value = null;
  };

  const mapMediaError = mediaError => {
    const name = mediaError?.name || '';
    if (name === 'NotAllowedError' || name === 'PermissionDeniedError') {
      return 'PERMISSION';
    }
    if (name === 'NotFoundError' || name === 'DevicesNotFoundError') {
      return 'NOT_FOUND';
    }
    return 'GENERIC';
  };

  const releaseOrphanStream = mediaStream => {
    mediaStream?.getTracks()?.forEach(track => track.stop());
  };

  const startStream = async () => {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
      error.value = 'GENERIC';
      return null;
    }

    stopStream();
    clearCapturedPreview();
    error.value = null;

    const generation = startGeneration;
    isStarting.value = true;
    isVideoReady.value = false;

    try {
      const mediaStream =
        await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);

      // Dialog closed (or retake/reset) while the permission prompt was open.
      if (generation !== startGeneration) {
        releaseOrphanStream(mediaStream);
        return null;
      }

      stream.value = mediaStream;
      return mediaStream;
    } catch (mediaError) {
      if (generation !== startGeneration) {
        return null;
      }
      error.value = mapMediaError(mediaError);
      stopStream();
      return null;
    } finally {
      if (generation === startGeneration) {
        isStarting.value = false;
      }
    }
  };

  const markVideoReady = ready => {
    isVideoReady.value = Boolean(ready);
  };

  const capturePhoto = async videoEl => {
    if (!videoEl || !videoEl.videoWidth || !videoEl.videoHeight) {
      error.value = 'GENERIC';
      return null;
    }

    const canvas = document.createElement('canvas');
    canvas.width = videoEl.videoWidth;
    canvas.height = videoEl.videoHeight;
    const context = canvas.getContext('2d');
    if (!context) {
      error.value = 'GENERIC';
      return null;
    }

    context.drawImage(videoEl, 0, 0);

    const blob = await new Promise(resolve => {
      canvas.toBlob(resolve, 'image/jpeg', 0.92);
    });

    if (!blob) {
      error.value = 'GENERIC';
      return null;
    }

    const file = new File([blob], `webcam-${getUuid()}.jpg`, {
      type: 'image/jpeg',
    });

    clearCapturedPreview();
    capturedFile.value = file;
    capturedPreviewUrl.value = URL.createObjectURL(blob);
    stopStream();
    return file;
  };

  const retake = async () => {
    clearCapturedPreview();
    return startStream();
  };

  onUnmounted(() => {
    reset();
  });

  return {
    stream,
    isStarting,
    isVideoReady,
    error,
    capturedFile,
    capturedPreviewUrl,
    startStream,
    stopStream,
    markVideoReady,
    capturePhoto,
    retake,
    reset,
    clearCapturedPreview,
  };
};
