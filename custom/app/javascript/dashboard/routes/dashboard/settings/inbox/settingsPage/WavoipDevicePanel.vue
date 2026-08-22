<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import InboxesAPI from 'dashboard/api/inboxes';
import {
  exportWavoipDiagnostics,
  getRecentConnectivityIssues,
} from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { formatWavoipDeviceActionError } from 'customDashboard/lib/wavoip/wavoipDeviceActionError';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { getWavoipClientEntry } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  hasWavoipDeviceActiveCalls,
  setWavoipWhatsAppStatus,
  useWavoipDeviceStatus,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { normalizeWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatusNormalize';
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

const emit = defineEmits(['update:liveDeviceStatus']);

const POLL_MS = 5000;
const WAVOIP_PANEL_URL = 'https://app.wavoip.com/devices';
const BAD_DEVICE_STATUSES = new Set([
  'WAITING_PAYMENT',
  'EXTERNAL_INTEGRATION_ERROR',
  'error',
]);
const PREPARING_STATUSES = new Set(['BUILDING', 'restarting', 'no_status']);

const { t } = useI18n();
const store = useStore();
const { replaceInstallationName } = useBranding();
const { wakeUpInboxDevice, disconnectInbox, connectInbox } =
  useWavoipConnection();

const inboxId = computed(() => props.inbox.id);
const deviceLive = computed(() => useWavoipDeviceStatus(inboxId.value));

const isLoading = ref(true);
const isVerifying = ref(false);
const isWaking = ref(false);
const isRestarting = ref(false);
const isLoggingOut = ref(false);
const isCopyingDiagnostics = ref(false);
const isTestingWebhook = ref(false);
const isRegeneratingWebhook = ref(false);
const isQrModalOpen = ref(false);
const qrModalFetchFresh = ref(false);
const statusVerifiedLive = ref(false);
const polledDeviceStatus = ref(null);
const preparingElapsedSeconds = ref(0);
const diagnosticsOpen = ref(false);
const restartDialogRef = ref(null);
const logoutDialogRef = ref(null);
let pollTimer = null;
let preparingTimer = null;
let preparingStartedAt = null;
let refreshPromise = null;
let pendingForceRefresh = false;
let panelOpenedSdkConnection = false;

const webhookUrl = computed(
  () => props.inbox.wavoip_webhook_url || props.inbox.wavoipWebhookUrl || ''
);

const whatsAppStatus = computed(() => {
  const live = deviceLive.value.whatsAppStatus.value;
  const raw =
    live ||
    polledDeviceStatus.value ||
    props.inbox.provider_config?.device_status ||
    'connecting';
  return normalizeWavoipDeviceStatus(raw);
});

const isConnected = computed(() => whatsAppStatus.value === 'open');
const isHibernating = computed(() => whatsAppStatus.value === 'hibernating');
const isPreparing = computed(() =>
  PREPARING_STATUSES.has(whatsAppStatus.value)
);
const isPreparingStuck = computed(
  () => isPreparing.value && preparingElapsedSeconds.value >= 90
);
const badStatusKey = computed(() => {
  const status = whatsAppStatus.value;
  if (!BAD_DEVICE_STATUSES.has(status)) return null;
  return status;
});

const linkedPhone = computed(() =>
  isConnected.value ? props.inbox.phone_number || '' : ''
);

const statusLabel = computed(() => {
  const key = (whatsAppStatus.value || 'unknown').toUpperCase();
  return t(`INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.${key}`, key);
});

const preparingHint = computed(() => {
  if (!isPreparing.value) return '';
  return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PREPARING_HINT', {
    seconds: preparingElapsedSeconds.value,
  });
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
  () =>
    isWaking.value ||
    isRestarting.value ||
    isLoggingOut.value ||
    isVerifying.value
);

const isDestructiveBlocked = computed(
  () => isBusy.value || hasActiveDeviceCalls.value
);

const recentIssues = computed(() =>
  getRecentConnectivityIssues(inboxId.value).slice(-5)
);

function startPreparingTimer() {
  if (preparingTimer) return;
  preparingStartedAt = Date.now();
  preparingElapsedSeconds.value = 0;
  preparingTimer = setInterval(() => {
    preparingElapsedSeconds.value = Math.floor(
      (Date.now() - preparingStartedAt) / 1000
    );
  }, 1000);
}

function stopPreparingTimer() {
  if (preparingTimer) {
    clearInterval(preparingTimer);
    preparingTimer = null;
  }
  preparingStartedAt = null;
  preparingElapsedSeconds.value = 0;
}

watch(
  whatsAppStatus,
  status => {
    emit('update:liveDeviceStatus', status);
    if (PREPARING_STATUSES.has(status)) {
      startPreparingTimer();
    } else {
      stopPreparingTimer();
    }
  },
  { immediate: true }
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

async function syncInboxWhenStatusDiverges(deviceStatus) {
  if (!inboxId.value || !deviceStatus) return;

  const inboxStatus = normalizeWavoipDeviceStatus(
    props.inbox.provider_config?.device_status || props.inbox.device_status
  );
  if (inboxStatus === deviceStatus) return;

  try {
    await store.dispatch('inboxes/fetchInboxItem', inboxId.value);
  } catch {
    /* checklist may stay briefly stale until the next navigation */
  }
}

async function refreshConnection({ forceLiveCheck = false } = {}) {
  if (refreshPromise) {
    if (forceLiveCheck) pendingForceRefresh = true;
    return refreshPromise.then(() => {
      if (!pendingForceRefresh) return undefined;
      pendingForceRefresh = false;
      return refreshConnection({ forceLiveCheck: true });
    });
  }

  refreshPromise = (async () => {
    try {
      const { data } = await InboxesAPI.getWavoipDeviceStatus(inboxId.value, {
        force: forceLiveCheck,
      });
      statusVerifiedLive.value = data?.live === true;
      if (data?.device_status) {
        const normalized = normalizeWavoipDeviceStatus(data.device_status);
        polledDeviceStatus.value = normalized;
        if (!deviceLive.value.whatsAppStatus.value) {
          setWavoipWhatsAppStatus(inboxId.value, normalized);
        }
        await syncInboxWhenStatusDiverges(normalized);
      }
    } catch {
      statusVerifiedLive.value = false;
    } finally {
      isLoading.value = false;
      isVerifying.value = false;
    }
  })().finally(() => {
    refreshPromise = null;
  });

  return refreshPromise;
}

const handleVerifyAgain = async () => {
  isVerifying.value = true;
  await refreshConnection({ forceLiveCheck: true });
};

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
  await refreshConnection({ forceLiveCheck: true });
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
    const payload = exportWavoipDiagnostics({
      inboxId: inboxId.value,
      panelStatus: whatsAppStatus.value,
      statusVerifiedLive: statusVerifiedLive.value,
    });
    await navigator.clipboard.writeText(payload);
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.COPIED'));
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isCopyingDiagnostics.value = false;
  }
};

const testWebhook = async () => {
  if (isTestingWebhook.value || !inboxId.value) return;
  isTestingWebhook.value = true;
  try {
    const { data } = await InboxesAPI.testWavoipWebhook(inboxId.value);
    await store.dispatch('inboxes/fetchInboxItem', inboxId.value);
    if (data?.webhook_verified) {
      useAlert(t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.TEST_SUCCESS'));
    } else {
      useAlert(t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.TEST_PENDING'));
    }
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isTestingWebhook.value = false;
  }
};

const regenerateWebhookKey = async () => {
  if (isRegeneratingWebhook.value || !inboxId.value) return;
  // eslint-disable-next-line no-alert
  const confirmed = window.confirm(
    t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.REGENERATE_CONFIRM')
  );
  if (!confirmed) return;

  isRegeneratingWebhook.value = true;
  try {
    await InboxesAPI.regenerateWavoipWebhookKey(inboxId.value);
    await store.dispatch('inboxes/fetchInboxItem', inboxId.value);
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.REGENERATE_SUCCESS'));
  } catch (error) {
    showDeviceActionError(error);
  } finally {
    isRegeneratingWebhook.value = false;
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
  stopPreparingTimer();
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
        <p v-if="isPreparing" class="text-n-slate-11">
          {{ preparingHint }}
        </p>
        <div
          v-if="
            isHibernating ||
            hasActiveDeviceCalls ||
            showStaleStatusHint ||
            isPreparingStuck ||
            badStatusKey
          "
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
          <span
            v-if="isPreparingStuck"
            class="inline-flex items-center gap-1 rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            <Icon icon="i-ph-warning-bold" class="size-3 shrink-0" />
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PREPARING_STUCK') }}
          </span>
          <span
            v-if="badStatusKey === 'WAITING_PAYMENT'"
            class="inline-flex items-center gap-1 rounded-full bg-n-ruby-3 px-2 py-0.5 text-xs font-medium text-n-ruby-11"
          >
            <Icon icon="i-ph-warning-bold" class="size-3 shrink-0" />
            {{
              $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WAITING_PAYMENT_HINT')
            }}
          </span>
          <span
            v-else-if="badStatusKey === 'EXTERNAL_INTEGRATION_ERROR'"
            class="inline-flex items-center gap-1 rounded-full bg-n-ruby-3 px-2 py-0.5 text-xs font-medium text-n-ruby-11"
          >
            <Icon icon="i-ph-warning-bold" class="size-3 shrink-0" />
            {{
              $t(
                'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.EXTERNAL_INTEGRATION_ERROR_HINT'
              )
            }}
          </span>
          <span
            v-else-if="badStatusKey === 'error'"
            class="inline-flex items-center gap-1 rounded-full bg-n-ruby-3 px-2 py-0.5 text-xs font-medium text-n-ruby-11"
          >
            <Icon icon="i-ph-warning-bold" class="size-3 shrink-0" />
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ERROR_HINT') }}
          </span>
        </div>
        <a
          v-if="badStatusKey"
          :href="WAVOIP_PANEL_URL"
          target="_blank"
          rel="noopener noreferrer"
          class="text-sm text-n-brand underline"
        >
          {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.OPEN_WAVOIP_PANEL') }}
        </a>
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <NextButton
          v-if="showStaleStatusHint"
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.VERIFY_AGAIN')"
          :is-loading="isVerifying"
          :disabled="isBusy"
          @click="handleVerifyAgain"
        />
        <NextButton
          v-if="!isConnected"
          sm
          :faded="showStaleStatusHint || isPreparingStuck"
          :slate="showStaleStatusHint || isPreparingStuck"
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
          :faded="!isPreparingStuck"
          :slate="!isPreparingStuck"
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
      :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.LABEL')"
      :help-text="
        replaceInstallationName($t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.HELP_TEXT'))
      "
    >
      <woot-code v-if="webhookUrl" :script="webhookUrl" lang="html" />
      <p v-else class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.UNAVAILABLE') }}
      </p>
      <div class="mt-3 flex flex-wrap gap-2">
        <NextButton
          v-if="webhookUrl"
          faded
          slate
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.TEST')"
          :is-loading="isTestingWebhook"
          @click="testWebhook"
        />
        <NextButton
          v-if="webhookUrl"
          faded
          slate
          sm
          :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.REGENERATE')"
          :is-loading="isRegeneratingWebhook"
          @click="regenerateWebhookKey"
        />
        <a
          :href="WAVOIP_PANEL_URL"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center text-sm text-n-brand underline"
        >
          {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.OPEN_WAVOIP_PANEL') }}
        </a>
      </div>
    </SettingsFieldSection>

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

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.SECTION_LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.SECTION_HELP')"
    >
      <button
        type="button"
        class="text-sm text-n-brand underline"
        @click="diagnosticsOpen = !diagnosticsOpen"
      >
        {{
          diagnosticsOpen
            ? $t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.HIDE')
            : $t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.SHOW')
        }}
      </button>
      <div v-if="diagnosticsOpen" class="mt-3 flex flex-col gap-2 text-sm">
        <p class="text-n-slate-11">
          {{
            $t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.STATUS_LINE', {
              status: statusLabel,
              live: statusVerifiedLive
                ? $t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.LIVE_YES')
                : $t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.LIVE_NO'),
            })
          }}
        </p>
        <ul
          v-if="recentIssues.length"
          class="list-disc ps-5 text-n-slate-11 space-y-1"
        >
          <li v-for="(issue, index) in recentIssues" :key="index">
            {{ issue.issue || issue }}
          </li>
        </ul>
        <p v-else class="text-n-slate-11">
          {{ $t('INBOX_MGMT.WAVOIP_CALL.DIAGNOSTICS.NO_ISSUES') }}
        </p>
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
  </div>
</template>
