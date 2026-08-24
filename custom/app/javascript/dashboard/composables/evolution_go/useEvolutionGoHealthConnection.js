import { computed, onBeforeUnmount, ref, unref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { subscribeEvolutionGoConnection } from 'customDashboard/lib/evolution_go/evolutionGoCableRegistry';
import {
  isEvolutionPlaceholderPhone,
  normalizeEvolutionConnectionPayload,
  seedConnectionStateFromInbox,
} from 'customDashboard/lib/evolution/evolutionConnectionPayload';

const POLL_MS = 5000;
const MAX_POLL_FAILURES = 3;
const RATE_LIMIT_BACKOFF_MS = 30_000;

function resolveInboxRef(inboxRef) {
  const value = unref(inboxRef);
  return typeof value === 'function' ? value() : value;
}

function applySeedToState(inbox, { connectionStatus, phoneNumber }) {
  const seeded = seedConnectionStateFromInbox(inbox);
  if (seeded.connectionStatus) {
    connectionStatus.value = seeded.connectionStatus;
  }
  if (seeded.phoneNumber) {
    phoneNumber.value = seeded.phoneNumber;
  }
  return seeded;
}

function isRateLimited(error) {
  return error?.response?.status === 429;
}

export function useEvolutionGoHealthConnection(inboxRef, { qrModalRef } = {}) {
  const store = useStore();
  const { t } = useI18n();

  const connectionStatus = ref('connecting');
  const phoneNumber = ref('');
  const isLoading = ref(true);
  const isReconnecting = ref(false);
  const isLoggingOut = ref(false);
  const isSyncingWebhook = ref(false);
  const isQrModalOpen = ref(false);
  const qrModalFetchFresh = ref(false);
  const staleData = ref(false);
  const confirmTitle = ref('');
  const confirmDescription = ref('');

  let pollTimer = null;
  let rateLimitTimer = null;
  let pollFailureCount = 0;
  let refreshInFlight = null;
  let unsubscribeCable = null;

  const inboxId = computed(() => resolveInboxRef(inboxRef)?.id);
  const isConnected = computed(() => connectionStatus.value === 'open');
  const isBusy = computed(
    () => isReconnecting.value || isLoggingOut.value || isSyncingWebhook.value
  );

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function clearRateLimitTimer() {
    if (rateLimitTimer) {
      clearTimeout(rateLimitTimer);
      rateLimitTimer = null;
    }
  }

  function applyPhoneFromPayload(payload, normalized) {
    const phone =
      normalized.phoneNumber || payload.phoneNumber || payload.phone_number;
    if (phone && !isEvolutionPlaceholderPhone(phone)) {
      phoneNumber.value = phone;
    }
  }

  async function refreshInboxRecord() {
    if (!inboxId.value) return;
    try {
      await store.dispatch('inboxes/fetchInboxItem', inboxId.value);
    } catch {
      // Connection payload already applied; store refresh is best-effort.
    }
  }

  function fetchConnectionPayload() {
    if (refreshInFlight) return refreshInFlight;
    refreshInFlight = store
      .dispatch('inboxes/fetchEvolutionGoConnection', inboxId.value)
      .finally(() => {
        refreshInFlight = null;
      });
    return refreshInFlight;
  }

  async function applyPayload(payload) {
    if (isQrModalOpen.value) {
      qrModalRef?.value?.applyPayload?.(payload);
    }

    const normalized = normalizeEvolutionConnectionPayload(payload) || {};

    if (normalized.connectionStatus) {
      if (
        connectionStatus.value === 'open' &&
        normalized.connectionStatus === 'connecting' &&
        !isQrModalOpen.value
      ) {
        applyPhoneFromPayload(payload, normalized);
        return;
      }

      const wasConnected = isConnected.value;
      connectionStatus.value = normalized.connectionStatus;

      if (isConnected.value && !wasConnected) {
        applyPhoneFromPayload(payload, normalized);
        stopPolling();
        isQrModalOpen.value = false;
        if (!phoneNumber.value) {
          try {
            const full = await fetchConnectionPayload();
            applyPhoneFromPayload(
              full,
              normalizeEvolutionConnectionPayload(full) || {}
            );
          } catch {
            applyPhoneFromPayload(payload, normalized);
          }
        }
        await refreshInboxRecord();
      }
    }

    applyPhoneFromPayload(payload, normalized);
  }

  async function refreshConnection() {
    if (!inboxId.value) return;

    try {
      const payload = await fetchConnectionPayload();
      await applyPayload(payload);
      pollFailureCount = 0;
      staleData.value = false;
    } catch (error) {
      pollFailureCount += 1;
      applySeedToState(resolveInboxRef(inboxRef), {
        connectionStatus,
        phoneNumber,
      });
      if (isRateLimited(error)) {
        // eslint-disable-next-line no-use-before-define -- backoff resumes startPolling
        scheduleRateLimitBackoff();
      }
      if (pollFailureCount === MAX_POLL_FAILURES) {
        staleData.value = true;
        useAlert(
          error?.response?.data?.error ||
            t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.STALE_DATA')
        );
      }
    } finally {
      isLoading.value = false;
    }
  }

  function startPolling() {
    if (isQrModalOpen.value || isConnected.value || rateLimitTimer) return;
    stopPolling();
    pollTimer = setInterval(refreshConnection, POLL_MS);
  }

  function scheduleRateLimitBackoff() {
    stopPolling();
    if (rateLimitTimer) return;
    rateLimitTimer = setTimeout(() => {
      rateLimitTimer = null;
      if (!isConnected.value && !isQrModalOpen.value) {
        refreshConnection().then(() => startPolling());
      }
    }, RATE_LIMIT_BACKOFF_MS);
  }

  function openQrModal({ fresh = false } = {}) {
    stopPolling();
    qrModalFetchFresh.value = fresh;
    isQrModalOpen.value = true;
  }

  async function runAction(action, busyFlag) {
    if (busyFlag.value) return false;
    busyFlag.value = true;
    try {
      const payload = await store.dispatch(`inboxes/${action}`, inboxId.value);
      await applyPayload(payload);
      await refreshInboxRecord();
      useAlert(t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.ACTION_SUCCESS'));
      return true;
    } catch (error) {
      useAlert(
        error?.response?.data?.error || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
      );
      return false;
    } finally {
      busyFlag.value = false;
    }
  }

  async function reconnect() {
    isReconnecting.value = true;
    openQrModal({ fresh: true });
  }

  async function logout(confirmDialog) {
    confirmTitle.value = t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT');
    confirmDescription.value = t(
      'INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT_CONFIRM'
    );
    const ok = await confirmDialog?.showConfirmation();
    if (!ok) return;
    await runAction('evolutionGoLogout', isLoggingOut);
    phoneNumber.value = '';
    startPolling();
  }

  async function syncWebhook() {
    if (!inboxId.value || isSyncingWebhook.value) return;

    isSyncingWebhook.value = true;
    try {
      await store.dispatch('inboxes/evolutionGoSyncWebhook', inboxId.value);
      useAlert(
        t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.SYNC_WEBHOOK_SUCCESS')
      );
    } catch (error) {
      useAlert(
        error?.response?.data?.error ||
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.SYNC_WEBHOOK_ERROR')
      );
    } finally {
      isSyncingWebhook.value = false;
    }
  }

  function onQrConnected() {
    isReconnecting.value = false;
    isQrModalOpen.value = false;
    if (isConnected.value) {
      refreshInboxRecord();
      return;
    }
    refreshConnection().then(() => startPolling());
  }

  watch(
    () => resolveInboxRef(inboxRef)?.id,
    id => {
      unsubscribeCable?.();
      unsubscribeCable = null;
      if (!id) {
        isLoading.value = false;
        return;
      }

      const inbox = resolveInboxRef(inboxRef);
      unsubscribeCable = subscribeEvolutionGoConnection(id, applyPayload, {
        store,
      });
      const seeded = applySeedToState(inbox, { connectionStatus, phoneNumber });
      isLoading.value = !seeded.connectionStatus;
      refreshConnection().then(() => startPolling());
    },
    { immediate: true }
  );

  watch(isQrModalOpen, open => {
    if (open) {
      stopPolling();
    } else {
      isReconnecting.value = false;
      if (!isConnected.value) {
        startPolling();
      }
    }
  });

  onBeforeUnmount(() => {
    stopPolling();
    clearRateLimitTimer();
    unsubscribeCable?.();
  });

  return {
    connectionStatus,
    phoneNumber,
    isLoading,
    isReconnecting,
    isLoggingOut,
    isSyncingWebhook,
    isQrModalOpen,
    qrModalFetchFresh,
    staleData,
    confirmTitle,
    confirmDescription,
    isConnected,
    isBusy,
    reconnect,
    logout,
    syncWebhook,
    openQrModal,
    onQrConnected,
    refreshConnection,
  };
}
