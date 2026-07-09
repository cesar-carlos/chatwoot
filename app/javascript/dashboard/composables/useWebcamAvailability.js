import { ref, onMounted, onUnmounted } from 'vue';

/**
 * Detects whether the browser can see at least one videoinput device.
 * Does not call getUserMedia — permission is requested only when capturing.
 */
export const useWebcamAvailability = () => {
  const hasWebcam = ref(false);

  const refreshDevices = async () => {
    if (
      typeof window === 'undefined' ||
      !window.isSecureContext ||
      !navigator.mediaDevices?.enumerateDevices
    ) {
      hasWebcam.value = false;
      return;
    }

    try {
      const devices = await navigator.mediaDevices.enumerateDevices();
      hasWebcam.value = devices.some(device => device.kind === 'videoinput');
    } catch {
      hasWebcam.value = false;
    }
  };

  onMounted(() => {
    refreshDevices();
    navigator.mediaDevices?.addEventListener?.('devicechange', refreshDevices);
  });

  onUnmounted(() => {
    navigator.mediaDevices?.removeEventListener?.(
      'devicechange',
      refreshDevices
    );
  });

  return { hasWebcam, refreshDevices };
};
