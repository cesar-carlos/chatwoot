import { ref, onMounted, onUnmounted } from 'vue';

/**
 * Detects whether the browser can see at least one videoinput device.
 * Does not call getUserMedia — permission is requested only when capturing.
 */
export const useWebcamAvailability = () => {
  const hasWebcam = ref(false);
  const isCameraDenied = ref(false);
  let permissionStatus = null;

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

  const refreshPermission = async () => {
    if (typeof navigator === 'undefined' || !navigator.permissions?.query) {
      isCameraDenied.value = false;
      return;
    }

    try {
      if (permissionStatus) permissionStatus.onchange = null;
      permissionStatus = await navigator.permissions.query({ name: 'camera' });
      isCameraDenied.value = permissionStatus.state === 'denied';
      permissionStatus.onchange = () => {
        isCameraDenied.value = permissionStatus.state === 'denied';
      };
    } catch {
      // Firefox and Safari throw for camera. Keep the button usable.
      isCameraDenied.value = false;
    }
  };

  onMounted(() => {
    refreshDevices();
    refreshPermission();
    navigator.mediaDevices?.addEventListener?.('devicechange', refreshDevices);
  });

  onUnmounted(() => {
    navigator.mediaDevices?.removeEventListener?.(
      'devicechange',
      refreshDevices
    );
    if (permissionStatus) permissionStatus.onchange = null;
  });

  return { hasWebcam, isCameraDenied, refreshDevices };
};
