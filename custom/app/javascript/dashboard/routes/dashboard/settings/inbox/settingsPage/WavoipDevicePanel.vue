<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { getPrimaryDevice } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import { exportWavoipDiagnostics } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { formatWavoipDeviceActionError } from 'customDashboard/lib/wavoip/wavoipDeviceActionError';
import WavoipQrScanModal from 'customDashboard/components/wavoip/WavoipQrScanModal.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const POLL_MS = 5000;

const { t } = useI18n();
const store = useStore();
const { connectInbox, disconnectInbox, wakeUpInboxDevice } =
  useWavoipConnection();

const inboxId = computed(() => props.inbox.id);
const isLoading = ref(true);
const isWaking = ref(false);
const isRestarting = ref(false);
const isLoggingOut = ref(false);
const isQrModalOpen = ref(false);
const qrModalFetchFresh = ref(false);
let pollTimer = null;

const whatsAppStatus = computed(
  () => props.inbox.provider_config?.device_status || 'connecting'
);

const isConnected = computed(() => whatsAppStatus.value === 'open');

const linkedPhone = computed(() =>
  isConnected.value ? props.inbox.phone_number || '' : ''
);

const connectionStatus = computed(() => {
  const entry = getWavoipDeviceStatus(inboxId.value);
  return entry.connectionStatus.value;
});

const isRestricted = computed(() => {
  const entry = getWavoipDeviceStatus(inboxId.value);
  return entry.isRestricted.value;
});

const restrictedUntil = computed(() => {
  const entry = getWavoipDeviceStatus(inboxId.value);
  return entry.restrictedUntil.value;
});

const statusLabel = computed(() => {
  const key = (whatsAppStatus.value || 'unknown').toUpperCase();
  return t(`INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.${key}`, key);
});

const connectionLabel = computed(() => {
  const key = (connectionStatus.value || 'unknown').toUpperCase();
  return t(`INBOX_MGMT.WAVOIP_CALL.CONNECTION_STATUS.${key}`, key);
});

const showConnectionStatus = computed(() => Boolean(connectionStatus.value));

const isBusy = computed(
  () => isWaking.value || isRestarting.value || isLoggingOut.value
);

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

async function refreshConnection() {
  try {
    await store.dispatch('inboxes/fetchInboxItem', inboxId.value);
  } catch {
    // keep last known state
  } finally {
    isLoading.value = false;
  }
}

function startPolling() {
  if (isQrModalOpen.value) return;
  stopPolling();
  pollTimer = setInterval(refreshConnection, POLL_MS);
}

function openQrModal({ fresh = false } = {}) {
  stopPolling();
  qrModalFetchFresh.value = fresh;
  isQrModalOpen.value = true;
}

function onQrSessionActive(active) {
  if (active) {
    stopPolling();
  } else if (!isConnected.value) {
    startPolling();
  }
}

async function onQrConnected() {
  await refreshConnection();
  isQrModalOpen.value = false;
}

watch(inboxId, () => {
  stopPolling();
  isLoading.value = true;
  refreshConnection().then(() => {
    if (!isConnected.value && !isQrModalOpen.value) {
      startPolling();
    }
  });
});

watch(isConnected, connected => {
  if (connected) {
    stopPolling();
  } else if (!isQrModalOpen.value) {
    startPolling();
  }
});

async function releaseDeviceConnection() {
  try {
    await disconnectInbox(inboxId.value);
  } catch {
    /* noop */
  }
}

function showDeviceActionError(error) {
  useAlert(formatWavoipDeviceActionError(error, t));
}

const handleWakeUp = async () => {
  isWaking.value = true;
  try {
    await wakeUpInboxDevice(inboxId.value);
    await refreshConnection();
    if (!isConnected.value) {
      openQrModal({ fresh: true });
    }
  } catch (error) {
    showDeviceActionError(error);
    await releaseDeviceConnection();
  } finally {
    isWaking.value = false;
  }
};

const handleRestart = async () => {
  /* eslint-disable no-alert -- native confirm matches Evolution health actions */
  if (
    !window.confirm(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART_CONFIRM'))
  ) {
    return;
  }
  /* eslint-enable no-alert */

  isRestarting.value = true;
  try {
    await connectInbox(inboxId.value);
    const device = getPrimaryDevice(getWavoipClient(inboxId.value));
    if (device?.restart) {
      await device.restart();
    }
    openQrModal({ fresh: true });
  } catch (error) {
    showDeviceActionError(error);
    await releaseDeviceConnection();
  } finally {
    isRestarting.value = false;
  }
};

const handleLogout = async () => {
  /* eslint-disable no-alert -- native confirm matches Evolution health actions */
  if (
    !window.confirm(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT_CONFIRM'))
  ) {
    return;
  }
  /* eslint-enable no-alert */

  isLoggingOut.value = true;
  try {
    await connectInbox(inboxId.value);
    const device = getPrimaryDevice(getWavoipClient(inboxId.value));
    if (device?.logout) {
      await device.logout();
    }
    await refreshConnection();
    openQrModal({ fresh: true });
  } catch (error) {
    showDeviceActionError(error);
    await releaseDeviceConnection();
  } finally {
    isLoggingOut.value = false;
  }
};

const copyDiagnostics = async () => {
  const payload = exportWavoipDiagnostics({ inboxId: inboxId.value });
  await navigator.clipboard.writeText(payload);
  useAlert(t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.COPIED'));
};

onMounted(() => {
  refreshConnection();
  startPolling();
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.HELP_TEXT')"
    >
      <div
        v-if="isLoading"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <Spinner class="size-4" />
        <span>{{ $t('INBOX_MGMT.WAVOIP_CALL.HEALTH.LOADING') }}</span>
      </div>
      <div v-else class="flex flex-col gap-2 text-sm">
        <div>
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WHATSAPP') }}:
          </span>
          <span class="font-medium">{{ statusLabel }}</span>
        </div>
        <div v-if="linkedPhone">
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LINKED_PHONE') }}:
          </span>
          <span class="font-medium">{{ linkedPhone }}</span>
        </div>
        <div v-if="showConnectionStatus">
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.CONNECTION_STATUS.LABEL') }}:
          </span>
          <span class="font-medium">{{ connectionLabel }}</span>
        </div>
        <p v-if="isRestricted" class="text-n-ruby-11">
          {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTRICTED') }}
          <span v-if="restrictedUntil">({{ restrictedUntil }})</span>
        </p>
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <NextButton
          v-if="!isConnected"
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RECONNECT')"
          :disabled="isBusy"
          @click="openQrModal({ fresh: true })"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WAKE_UP')"
          :is-loading="isWaking"
          :disabled="isBusy"
          @click="handleWakeUp"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART')"
          :is-loading="isRestarting"
          :disabled="isBusy"
          @click="handleRestart"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT')"
          :is-loading="isLoggingOut"
          :disabled="isBusy"
          @click="handleLogout"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.COPY')"
          @click="copyDiagnostics"
        />
      </div>
    </SettingsFieldSection>

    <WavoipQrScanModal
      v-model="isQrModalOpen"
      :inbox-id="inbox.id"
      :phone-number="inbox.phone_number"
      :fetch-fresh-qr="qrModalFetchFresh"
      @connected="onQrConnected"
      @session-active="onQrSessionActive"
    />

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_TITLE')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_HELP')"
    >
      <ul class="list-disc ps-5 text-sm text-n-slate-11 space-y-1">
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_TOGGLE') }}</li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_CALL_EVENT') }}</li>
        <li>
          {{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_DEVICE_EVENT') }}
        </li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_URL') }}</li>
      </ul>
    </SettingsFieldSection>
  </div>
</template>
