import { ref, unref } from 'vue';
import { normalizeEvolutionConnectionPayload } from 'customDashboard/lib/evolution/evolutionConnectionPayload';

const POLL_MS = 3000;
const QR_EXPIRY_MS = 45_000;

export function useEvolutionGoQrSession({ inboxId, store, onConnected }) {
  const connectionStatus = ref('connecting');
  const qrcodeBase64 = ref('');
  const pairingCode = ref('');
  const pairingPhone = ref('');
  const isLoading = ref(false);
  const isRefreshing = ref(false);
  const isRequestingPairing = ref(false);
  const qrRefreshError = ref(false);

  let pollTimer = null;
  let expiryTimer = null;
  let sessionStartedConnected = false;
  let hasEmittedConnected = false;
  let refreshInFlight = null;
  let sessionActive = false;
  let sessionGeneration = 0;

  function isConnected() {
    return connectionStatus.value === 'open';
  }

  function currentSessionActive(generation) {
    return sessionActive && generation === sessionGeneration;
  }

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
    }
    pollTimer = null;
  }

  function clearExpiryTimer() {
    if (expiryTimer) {
      clearTimeout(expiryTimer);
      expiryTimer = null;
    }
  }

  function stopSession() {
    sessionActive = false;
    sessionGeneration += 1;
    stopPolling();
    clearExpiryTimer();
    refreshInFlight = null;
  }

  function applyPayload(raw) {
    const normalized = normalizeEvolutionConnectionPayload(raw) || {};

    if (normalized.connectionStatus) {
      connectionStatus.value = normalized.connectionStatus;
    }
    if (normalized.qrcodeBase64) {
      qrcodeBase64.value = normalized.qrcodeBase64;
      pairingCode.value = '';
      qrRefreshError.value = false;
      // eslint-disable-next-line no-use-before-define -- re-arm expiry when fresh QR arrives
      armQrExpiryTimer();
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

  async function refreshConnection({ includeQr = false } = {}) {
    const id = unref(inboxId);
    if (!id || refreshInFlight) return refreshInFlight;

    isLoading.value = true;
    refreshInFlight = store
      .dispatch('inboxes/fetchEvolutionGoConnection', {
        inboxId: id,
        includeQr,
      })
      .then(payload => {
        applyPayload(payload);
      })
      .catch(error => {
        if (isInboxNotFoundError(error)) {
          handleInboxNotFound();
        } else {
          qrRefreshError.value = true;
        }
      })
      .finally(() => {
        isLoading.value = false;
        refreshInFlight = null;
      });

    return refreshInFlight;
  }

  async function requestNewQr() {
    const id = unref(inboxId);
    if (!id || isRefreshing.value) return;

    isRefreshing.value = true;
    try {
      const payload = await store.dispatch('inboxes/evolutionGoReconnect', id);
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
      if (sessionActive && !isConnected()) {
        // eslint-disable-next-line no-use-before-define -- paired QR expiry scheduling
        armQrExpiryTimer();
      }
    }
  }

  async function requestPairingCode(phone) {
    const id = unref(inboxId);
    const normalizedPhone = (phone || pairingPhone.value || '').replace(
      /\D/g,
      ''
    );
    if (!id || !normalizedPhone || isRequestingPairing.value) return;

    isRequestingPairing.value = true;
    try {
      const payload = await store.dispatch('inboxes/evolutionGoPair', {
        inboxId: id,
        phone: normalizedPhone,
      });
      applyPayload(payload);
      if (payload.pairing_code) {
        pairingCode.value = payload.pairing_code;
      }
      qrRefreshError.value = false;
    } catch (error) {
      if (isInboxNotFoundError(error)) {
        handleInboxNotFound();
      } else {
        qrRefreshError.value = true;
      }
    } finally {
      isRequestingPairing.value = false;
    }
  }

  function armQrExpiryTimer() {
    clearExpiryTimer();
    if (!sessionActive) return;

    const generation = sessionGeneration;
    expiryTimer = setTimeout(() => {
      if (!currentSessionActive(generation)) return;
      if (!isConnected()) {
        requestNewQr();
      }
    }, QR_EXPIRY_MS);
  }

  function startPolling() {
    stopPolling();
    if (!sessionActive) return;

    const generation = sessionGeneration;
    pollTimer = setInterval(() => {
      if (!currentSessionActive(generation)) {
        stopPolling();
        return;
      }
      refreshConnection({ includeQr: true });
    }, POLL_MS);
  }

  async function startSession({ fetchFreshQr = false } = {}) {
    sessionActive = true;
    const generation = sessionGeneration;
    sessionStartedConnected = isConnected();
    hasEmittedConnected = false;
    qrRefreshError.value = false;

    if (fetchFreshQr) {
      await requestNewQr();
    } else {
      await refreshConnection();
      if (!currentSessionActive(generation)) return;
      armQrExpiryTimer();
    }
    if (!currentSessionActive(generation)) return;
    startPolling();
  }

  return {
    connectionStatus,
    qrcodeBase64,
    pairingCode,
    pairingPhone,
    isLoading,
    isRefreshing,
    isRequestingPairing,
    qrRefreshError,
    refreshConnection,
    requestNewQr,
    requestPairingCode,
    startSession,
    stopSession,
    applyPayload,
  };
}
