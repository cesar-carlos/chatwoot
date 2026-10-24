import { ref, onUnmounted } from 'vue';
import getUuid from 'widget/helpers/uuid';

const JPEG_QUALITY = 0.92;
const MAX_CAPTURE_EDGE = 1920;

const VIDEO_CONSTRAINTS = {
  audio: false,
  video: {
    facingMode: { ideal: 'user' },
    width: { ideal: 1280 },
    height: { ideal: 720 },
  },
};

// The dialog mounts on the first click, one tick after the gesture. Safari
// drops getUserMedia once that tick passes, so the click primes the request
// and startStream adopts it.
let primedStreamRequest = null;

const stopMediaStream = mediaStream => {
  mediaStream?.getTracks()?.forEach(track => track.stop());
};

export const releasePrimedWebcamStream = () => {
  const request = primedStreamRequest;
  primedStreamRequest = null;
  if (!request) return;
  request.then(stopMediaStream).catch(() => {});
};

export const primeWebcamStream = () => {
  releasePrimedWebcamStream();

  if (
    typeof window === 'undefined' ||
    !window.isSecureContext ||
    !navigator.mediaDevices?.getUserMedia
  ) {
    primedStreamRequest = Promise.resolve(null);
    return primedStreamRequest;
  }

  primedStreamRequest = navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);
  // Attach a catch so a rejection before startStream awaits it is not unhandled.
  primedStreamRequest.catch(() => {});
  return primedStreamRequest;
};

const takePrimedWebcamStream = () => {
  const request = primedStreamRequest;
  primedStreamRequest = null;
  return request;
};

const fitWithinMaxEdge = (width, height) => {
  const longest = Math.max(width, height);
  if (longest <= MAX_CAPTURE_EDGE) return { width, height };

  const scale = MAX_CAPTURE_EDGE / longest;
  return {
    width: Math.max(1, Math.round(width * scale)),
    height: Math.max(1, Math.round(height * scale)),
  };
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
    stopMediaStream(mediaStream);
  };

  const failCapture = () => {
    error.value = 'GENERIC';
    stopStream();
    return null;
  };

  const startStream = async () => {
    const primed = takePrimedWebcamStream();

    if (
      !primed &&
      (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia)
    ) {
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
      const mediaStream = primed
        ? await primed
        : await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);

      // Dialog closed (or retake/reset) while the permission prompt was open.
      if (generation !== startGeneration) {
        releaseOrphanStream(mediaStream);
        return null;
      }

      if (!mediaStream) {
        error.value = 'GENERIC';
        stopStream();
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
    if (!videoEl?.videoWidth || !videoEl.videoHeight) {
      return failCapture();
    }

    const generation = startGeneration;
    const { width, height } = fitWithinMaxEdge(
      videoEl.videoWidth,
      videoEl.videoHeight
    );
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d');
    if (!context) {
      return failCapture();
    }

    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    context.drawImage(videoEl, 0, 0, width, height);

    const blob = await new Promise(resolve => {
      canvas.toBlob(resolve, 'image/jpeg', JPEG_QUALITY);
    });

    if (generation !== startGeneration) return null;

    if (!blob) {
      return failCapture();
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
