import { ref, computed, onUnmounted, getCurrentInstance } from 'vue';

/**
 * Client-side countdown mirroring the server contacts-refresh Redis lock.
 * Keeps the settings "Refresh contact profiles" button disabled until ETA.
 */
export function useContactsRefreshLock() {
  const remainingSeconds = ref(0);
  let timer = null;

  const isLocked = computed(() => remainingSeconds.value > 0);

  function clearTimer() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  }

  function startCountdown(seconds) {
    clearTimer();
    const next = Math.max(0, Math.ceil(Number(seconds) || 0));
    remainingSeconds.value = next;
    if (next <= 0) return;

    timer = setInterval(() => {
      remainingSeconds.value = Math.max(0, remainingSeconds.value - 1);
      if (remainingSeconds.value <= 0) clearTimer();
    }, 1000);
  }

  function syncFromStatus(status) {
    if (status?.running && status.remaining_seconds > 0) {
      startCountdown(status.remaining_seconds);
      return;
    }
    if (status && !status.running) {
      clearTimer();
      remainingSeconds.value = 0;
    }
  }

  if (getCurrentInstance()) {
    onUnmounted(clearTimer);
  }

  return {
    remainingSeconds,
    isLocked,
    startCountdown,
    syncFromStatus,
  };
}

export function isContactsRefreshAlreadyRunningError(error) {
  const data = error?.response?.data;
  if (data?.code === 'already_running') return true;
  const message = String(data?.error || '');
  return /already running/i.test(message);
}
