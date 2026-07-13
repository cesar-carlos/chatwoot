<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import { exportWavoipDiagnostics } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { formatWavoipDeviceActionError } from 'customDashboard/lib/wavoip/wavoipDeviceActionError';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { getWavoipClientEntry } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  hasWavoipDeviceActiveCalls,
  useWavoipDeviceStatus,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import WavoipQrScanModal from 'customDashboard/components/wavoip/WavoipQrScanModal.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const POLL_MS = 5000;

const { t } = useI18n();
const { wakeUpInboxDevice, disconnectInbox, connectInbox } =
  useWavoipConnection();

const inboxId = computed(() => props.inbox.id);
const deviceLive = computed(() => useWavoipDeviceStatus(inboxId.value));

const isLoading = ref(true);
const isWaking = ref(false);
const isRestarting = ref(false);
const isLoggingOut = ref(false);
const isCopyingDiagnostics = ref(false);
const isQrModalOpen = ref(false);
const qrModalFetchFresh = ref(false);
const statusVerifiedLive = ref(false);
const polledDeviceStatus = ref(null);
const restartDialogRef = ref(null);
const logoutDialogRef = ref(null);
let pollTimer = null;
let refreshPromise = null;
let panelOpenedSdkConnection = false;

const whatsAppStatus = computed(() => {
  const live = deviceLive.value.whatsAppStatus.value;
  if (live) return live;
  if (polledDeviceStatus.value) return polledDeviceStatus.value;
  return props.inbox.provider_config?.device_status || 'connecting';
});

const isConnected = computed(() => whatsAppStatus.value === 'open');
const isHibernating = computed(() => whatsAppStatus.value === 'hibernating');

const linkedPhone = computed(() =>
  isConnected.value ? props.inbox.phone_number || '' : ''
);

const statusLabel = computed(() => {
  const key = (whatsAppStatus.value || 'unknown').toUpperCase();
  return t(`INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.${key}`, key);
});

const activeCallsCount = computed(
  () => deviceLive.value.activeCalls.value ?? 0
);

const numChannels = computed(() => deviceLive.value.numChannels.value);

const activeCallsLabel = computed(() => {
  if (!isConnected.value) return '';
  const active = activeCallsCount.value;
  const total = numChannels.value;
  if (total) {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ACTIVE_CALLS', {
      active,
      total,
    });
  }
  if (active > 0) {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ACTIVE_CALLS_ONLY', {
      active,
    });
  }
  return '';
});

const showStaleStatusHint = computed(
  () => !isLoading.value && !statusVerifiedLive.value
);

const hasActiveDeviceCalls = computed(() =>
  hasWavoipDeviceActiveCalls(inboxId.value)
);

const isBusy = computed(
  () => isWaking.value || isRestarting.value || isLoggingOut.value
);

const isDestructiveBlocked = computed(
  () => isBusy.value || hasActiveDeviceCalls.value
);

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

async function ensurePanelSdkConnection() {
  if (!inboxId.value) return;
  if (getWavoipClientEntry(inboxId.value)) return;

  const status = whatsAppStatus.value;
  if (status !== 'open' && status !== 'hibernating') return;

  try {
    await connectInbox(inboxId.value);
    panelOpenedSdkConnection = true;
  } catch {
    /* live channel stats are optional on the settings page */
  }
}

async function refreshConnection({ forceLiveCheck = false } = {}) {
  if (refreshPromise) return refreshPromise;

  refreshPromise = (async () => {
    try {
      const { data } = await InboxesAPI.getWavoipDeviceStatus(inboxId.value, {
        force: forceLiveCheck,
      });
      statusVerifiedLive.value = data?.live === true;
      if (data?.device_status) {
        polledDeviceStatus.value = data.device_status;
      }
    } catch {
      statusVerifiedLive.value = false;
    } finally {
      isLoading.value = false;
    }
  })().finally(() => {
    refreshPromise = null;
  });

  return refreshPromise;
}

function startPolling() {
  if (isQrModalOpen.value) return;
  stopPolling();
  pollTimer = setInterval(
    () => refreshConnection({ forceLiveCheck: false }),
    POLL_MS
  );
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
  polledDeviceStatus.value = null;
  isLoading.value = true;
  refreshConnection({ forceLiveCheck: true }).then(async () => {
    await ensurePanelSdkConnection();
    if (!isConnected.value && !isQrModalOpen.value) {
      startPolling();
    }
  });
});

watch(isConnected, connected => {
  if (connected) {
    stopPolling();
    ensurePanelSdkConnection();
  } else if (!isQrModalOpen.value) {
    startPolling();
  }
});

function showDeviceActionError(error) {
  useAlert(formatWavoipDeviceActionError(error, t));
}

function blockIfActiveCalls() {
  if (!hasActiveDeviceCalls.value) return false;
  useAlert(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.BLOCKED_ACTIVE_CALLS'));
  return true;
}

const handleWakeUp = async () => {
  isWaking.value = true;
  const hadSdkConnection = Boolean(getWavoipClientEntry(inboxId.value));
  try {
    await wakeUpInboxDevice(inboxId.value);
    if (!hadSdkConnection) {
      panelOpenedSdkConnection = true;
    }
    await refreshConnection({ forceLiveCheck: true });
    // Wake is only for hibernation. If WhatsApp still isn't open (e.g. session
    // dropped to close), fall through to the QR pairing flow — without a hard
    // restart so Restart remains the explicit destructive action.
    if (!isConnected.value) {
      openQrModal({ fresh: false });
    }
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isWaking.value = false;
  }
};

const handleRestart = () => {
  if (blockIfActiveCalls()) return;
  restartDialogRef.value?.open();
};

const confirmRestart = async () => {
  isRestarting.value = true;
  try {
    await InboxesAPI.getWavoipQr(inboxId.value, { refresh: true });
    await refreshConnection({ forceLiveCheck: true });
    openQrModal({ fresh: false });
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isRestarting.value = false;
    restartDialogRef.value?.close();
  }
};

const handleLogout = () => {
  if (!isConnected.value) {
    openQrModal({ fresh: true });
    return;
  }

  if (blockIfActiveCalls()) return;
  logoutDialogRef.value?.open();
};

const confirmLogout = async () => {
  isLoggingOut.value = true;
  try {
    await InboxesAPI.postWavoipLogout(inboxId.value);
    await refreshConnection({ forceLiveCheck: true });
    openQrModal({ fresh: true });
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isLoggingOut.value = false;
    logoutDialogRef.value?.close();
  }
};

const copyDiagnostics = async () => {
  isCopyingDiagnostics.value = true;
  try {
    const payload = exportWavoipDiagnostics({ inboxId: inboxId.value });
    await navigator.clipboard.writeText(payload);
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.COPIED'));
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isCopyingDiagnostics.value = false;
  }
};

onMounted(() => {
  refreshConnection({ forceLiveCheck: true }).then(async () => {
    await ensurePanelSdkConnection();
    if (!isConnected.value && !isQrModalOpen.value) {
      startPolling();
    }
  });
});

onBeforeUnmount(() => {
  stopPolling();
  if (panelOpenedSdkConnection) {
    disconnectInbox(inboxId.value).catch(() => {});
    panelOpenedSdkConnection = false;
  }
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
        <div v-if="activeCallsLabel">
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ACTIVE_CALLS_LABEL') }}:
          </span>
          <span class="font-medium">{{ activeCallsLabel }}</span>
        </div>
        <div
          v-if="isHibernating || hasActiveDeviceCalls || showStaleStatusHint"
          class="flex flex-wrap gap-1.5"
        >
          <span
            v-if="isHibernating"
            class="inline-flex items-center gap-1 rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            <Icon icon="i-ph-moon-bold" class="size-3 shrink-0" />
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.HIBERNATING_HINT') }}
          </span>
          <span
            v-if="hasActiveDeviceCalls"
            class="inline-flex items-center gap-1 rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            <Icon icon="i-ph-phone-call-bold" class="size-3 shrink-0" />
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ACTIVE_CALLS_HINT') }}
          </span>
          <span
            v-if="showStaleStatusHint"
            class="inline-flex items-center gap-1 rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            <Icon icon="i-ph-warning-bold" class="size-3 shrink-0" />
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.STATUS_STALE') }}
          </span>
        </div>
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <NextButton
          v-if="!isConnected"
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RECONNECT')"
          :disabled="isBusy"
          @click="openQrModal({ fresh: false })"
        />
        <NextButton
          v-if="isHibernating"
          sm
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
          :disabled="isDestructiveBlocked"
          @click="handleRestart"
        />
        <NextButton
          v-if="isConnected"
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT')"
          :is-loading="isLoggingOut"
          :disabled="isDestructiveBlocked"
          @click="handleLogout"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.COPY')"
          :is-loading="isCopyingDiagnostics"
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

    <Dialog
      ref="restartDialogRef"
      type="alert"
      :title="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART_CONFIRM_TITLE')"
      :description="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART_CONFIRM')"
      :confirm-button-label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART')"
      :is-loading="isRestarting"
      @confirm="confirmRestart"
    />

    <Dialog
      ref="logoutDialogRef"
      type="alert"
      :title="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT_CONFIRM_TITLE')"
      :description="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT_CONFIRM')"
      :confirm-button-label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT')"
      :is-loading="isLoggingOut"
      @confirm="confirmLogout"
    />

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_TITLE')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_HELP')"
    >
      <ul class="list-disc ps-5 text-sm text-n-slate-11 space-y-1">
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_TOGGLE') }}</li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_CALL_EVENT') }}</li>
        <li>
          {{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_RECORD_EVENT') }}
        </li>
        <li>
          {{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_DEVICE_EVENT') }}
        </li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_URL') }}</li>
      </ul>
    </SettingsFieldSection>
  </div>
</template>
