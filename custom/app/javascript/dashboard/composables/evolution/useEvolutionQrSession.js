import { ref, unref } from 'vue';
import { normalizeEvolutionConnectionPayload } from 'customDashboard/lib/evolution/evolutionConnectionPayload';

/* eslint-disable no-use-before-define -- QR expiry timer and reconnect share callbacks */

const POLL_MS = 3000;
const QR_EXPIRY_MS = 45_000;

export function useEvolutionQrSession({ inboxId, store, onConnected }) {
  const connectionStatus = ref('connecting');
  const qrcodeBase64 = ref('');
  const pairingCode = ref('');
  const isLoading = ref(false);
  const isRefreshing = ref(false);
  const qrRefreshError = ref(false);

  let pollTimer = null;
  let expiryTimer = null;
  let sessionStartedConnected = false;
  let hasEmittedConnected = false;

  function isConnected() {
    return connectionStatus.value === 'open';
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function clearExpiryTimer() {
    if (expiryTimer) {
      clearTimeout(expiryTimer);
      expiryTimer = null;
    }
  }

  function stopSession() {
    stopPolling();
    clearExpiryTimer();
  }

  function applyPayload(raw) {
    const normalized = normalizeEvolutionConnectionPayload(raw) || {};

    if (normalized.connectionStatus) {
      connectionStatus.value = normalized.connectionStatus;
    }
    if (normalized.qrcodeBase64) {
      qrcodeBase64.value = normalized.qrcodeBase64;
      qrRefreshError.value = false;
    }
    if (normalized.pairingCode) {
      pairingCode.value = normalized.pairingCode;
    }

    if (isConnected()) {
      stopSession();
      if (!sessionStartedConnected && !hasEmittedConnected) {
        hasEmittedConnected = true;
        onConnected?.();
      }
    }
  }

  function isInboxNotFoundError(error) {
    return error?.response?.status === 404;
  }

  function handleInboxNotFound() {
    stopSession();
    qrRefreshError.value = true;
  }

  async function refreshConnection() {
    const id = unref(inboxId);
    if (!id) return;

    isLoading.value = true;
    try {
      const payload = await store.dispatch(
        'inboxes/fetchEvolutionConnection',
        id
      );
      applyPayload(payload);
    } catch (error) {
      if (isInboxNotFoundError(error)) {
        handleInboxNotFound();
      }
    } finally {
      isLoading.value = false;
    }
  }

  function armQrExpiryTimer() {
    clearExpiryTimer();
    expiryTimer = setTimeout(() => {
      if (!isConnected()) {
        requestNewQr();
      }
    }, QR_EXPIRY_MS);
  }

  async function requestNewQr() {
    const id = unref(inboxId);
    if (!id || isRefreshing.value) return;

    isRefreshing.value = true;
    try {
      const payload = await store.dispatch('inboxes/evolutionReconnect', id);
      applyPayload(payload);
      qrRefreshError.value = false;
    } catch (error) {
      if (isInboxNotFoundError(error)) {
        handleInboxNotFound();
      } else {
        qrRefreshError.value = true;
      }
    } finally {
      isRefreshing.value = false;
      if (!isConnected()) {
        armQrExpiryTimer();
      }
    }
  }

  function startPolling() {
    stopPolling();
    pollTimer = setInterval(refreshConnection, POLL_MS);
  }

  function startSession({ fetchFreshQr = false } = {}) {
    sessionStartedConnected = isConnected();
    hasEmittedConnected = false;
    qrRefreshError.value = false;

    if (fetchFreshQr) {
      requestNewQr();
    } else {
      refreshConnection();
      armQrExpiryTimer();
    }
    startPolling();
  }

  return {
    connectionStatus,
    qrcodeBase64,
    pairingCode,
    isLoading,
    isRefreshing,
    qrRefreshError,
    refreshConnection,
    requestNewQr,
    startSession,
    stopSession,
    applyPayload,
  };
}
