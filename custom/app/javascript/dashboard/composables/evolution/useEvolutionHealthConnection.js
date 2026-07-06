import { computed, onBeforeUnmount, ref, unref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useEvolutionConnectionCable } from 'customDashboard/composables/evolution/useEvolutionConnectionCable';
import {
  isEvolutionPlaceholderPhone,
  normalizeEvolutionConnectionPayload,
  seedConnectionStateFromInbox,
} from 'customDashboard/lib/evolution/evolutionConnectionPayload';

const POLL_MS = 5000;
const MAX_POLL_FAILURES = 3;

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

export function useEvolutionHealthConnection(inboxRef, { qrModalRef } = {}) {
  const store = useStore();
  const { t } = useI18n();

  const connectionStatus = ref('connecting');
  const phoneNumber = ref('');
  const isLoading = ref(true);
  const isLoggingOut = ref(false);
  const isRestarting = ref(false);
  const isQrModalOpen = ref(false);
  const qrModalFetchFresh = ref(false);
  const staleData = ref(false);
  const confirmTitle = ref('');
  const confirmDescription = ref('');

  let pollTimer = null;
  let pollFailureCount = 0;

  const inboxId = computed(() => unref(inboxRef)?.id);
  const isConnected = computed(() => connectionStatus.value === 'open');
  const isBusy = computed(() => isLoggingOut.value || isRestarting.value);

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function applyPhoneFromPayload(payload, normalized) {
    const phone =
      normalized.phoneNumber || payload.phoneNumber || payload.phone_number;
    if (phone && !isEvolutionPlaceholderPhone(phone)) {
      phoneNumber.value = phone;
    }
  }

  async function applyPayload(payload) {
    if (isQrModalOpen.value) {
      qrModalRef?.value?.applyPayload?.(payload);
    }

    const normalized = normalizeEvolutionConnectionPayload(payload) || {};

    if (normalized.connectionStatus) {
      const wasConnected = isConnected.value;
      connectionStatus.value = normalized.connectionStatus;

      if (isConnected.value && !wasConnected) {
        try {
          const full = await store.dispatch(
            'inboxes/fetchEvolutionConnection',
            inboxId.value
          );
          applyPhoneFromPayload(
            full,
            normalizeEvolutionConnectionPayload(full) || {}
          );
        } catch {
          applyPhoneFromPayload(payload, normalized);
        }
        stopPolling();
        isQrModalOpen.value = false;
        await store.dispatch('inboxes/get', inboxId.value);
      }
    }

    applyPhoneFromPayload(payload, normalized);
  }

  async function refreshConnection() {
    if (!inboxId.value) return;

    try {
      const payload = await store.dispatch(
        'inboxes/fetchEvolutionConnection',
        inboxId.value
      );
      await applyPayload(payload);
      pollFailureCount = 0;
      staleData.value = false;
    } catch (error) {
      pollFailureCount += 1;
      applySeedToState(unref(inboxRef), { connectionStatus, phoneNumber });
      if (pollFailureCount >= MAX_POLL_FAILURES) {
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
    if (isQrModalOpen.value || isConnected.value) return;
    stopPolling();
    pollTimer = setInterval(refreshConnection, POLL_MS);
  }

  useEvolutionConnectionCable(inboxId, applyPayload);

  watch(
    () => unref(inboxRef),
    inbox => {
      if (!inbox?.id) return;

      const seeded = applySeedToState(inbox, { connectionStatus, phoneNumber });
      isLoading.value = !seeded.connectionStatus;
      refreshConnection();
      startPolling();
    },
    { immediate: true }
  );

  watch(isQrModalOpen, open => {
    if (open) {
      stopPolling();
    } else if (!isConnected.value) {
      startPolling();
    }
  });

  onBeforeUnmount(stopPolling);

  function openQrModal({ fresh = false } = {}) {
    stopPolling();
    qrModalFetchFresh.value = fresh;
    isQrModalOpen.value = true;
  }

  async function onQrConnected() {
    await store.dispatch('inboxes/get', inboxId.value);
    await refreshConnection();
  }

  async function runAction(action, busyFlag) {
    if (busyFlag.value) return false;
    busyFlag.value = true;
    try {
      const payload = await store.dispatch(`inboxes/${action}`, inboxId.value);
      await applyPayload(payload);
      await store.dispatch('inboxes/get', inboxId.value);
      useAlert(t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.ACTION_SUCCESS'));
      return true;
    } catch (error) {
      useAlert(
        error.response?.data?.error || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
      );
      return false;
    } finally {
      busyFlag.value = false;
    }
  }

  function reconnect() {
    openQrModal({ fresh: true });
  }

  async function restart(confirmDialog) {
    confirmTitle.value = t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART');
    confirmDescription.value = t(
      'INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART_CONFIRM'
    );
    const ok = await confirmDialog?.showConfirmation();
    if (!ok) return;
    const succeeded = await runAction('evolutionRestart', isRestarting);
    // Only show the "scan to reconnect" flow when the restart actually
    // happened — surfacing the QR modal after a failed restart made it look
    // like the action had succeeded.
    if (succeeded) openQrModal({ fresh: true });
  }

  async function logout(confirmDialog) {
    confirmTitle.value = t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT');
    confirmDescription.value = t(
      'INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT_CONFIRM'
    );
    const ok = await confirmDialog?.showConfirmation();
    if (!ok) return;
    await runAction('evolutionLogout', isLoggingOut);
    phoneNumber.value = '';
    startPolling();
  }

  return {
    connectionStatus,
    phoneNumber,
    isLoading,
    isLoggingOut,
    isRestarting,
    isQrModalOpen,
    qrModalFetchFresh,
    staleData,
    confirmTitle,
    confirmDescription,
    isConnected,
    isBusy,
    reconnect,
    restart,
    logout,
    onQrConnected,
    applyPayload,
  };
}
