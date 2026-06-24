<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { useWavoipQrSession } from 'customDashboard/composables/wavoip/useWavoipQrSession';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { getPrimaryDevice } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import { exportWavoipDiagnostics } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import WavoipQrDisplay from 'customDashboard/components/wavoip/WavoipQrDisplay.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const { wakeUpInboxDevice } = useWavoipConnection();

const inboxId = computed(() => props.inbox.id);

const {
  whatsAppStatus,
  qrDataUrl,
  pairingCode,
  linkedPhone,
  isLoading,
  isRefreshing,
  qrRefreshError,
  needsQr,
  startSession,
  stopSession,
  requestPairingCode,
  refreshQr,
  clearQrState,
} = useWavoipQrSession({
  inboxId: computed(() => props.inbox.id),
  phoneNumber: computed(() => props.inbox.phone_number),
  onConnected: () => {
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.CONNECTED'));
  },
  onPhoneMismatch: () => {
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PHONE_MISMATCH'));
  },
});

const isWaking = ref(false);
const isRestarting = ref(false);
const isLoggingOut = ref(false);

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

const showQrSection = computed(
  () => needsQr() || Boolean(qrDataUrl.value) || Boolean(pairingCode.value)
);

watch(inboxId, () => {
  stopSession();
  clearQrState();
  startSession();
});

const handleWakeUp = async () => {
  isWaking.value = true;
  try {
    await wakeUpInboxDevice(inboxId.value);
    await refreshQr();
  } finally {
    isWaking.value = false;
  }
};

const handlePairingCode = async () => {
  try {
    await requestPairingCode();
  } catch (error) {
    useAlert(error?.message || t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.REFRESH_ERROR'));
  }
};

const handleRefreshQr = async () => {
  try {
    await refreshQr();
  } catch (error) {
    useAlert(error?.message || t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.REFRESH_ERROR'));
  }
};

const handleRestart = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART_CONFIRM'))) {
    return;
  }
  const device = getPrimaryDevice(getWavoipClient(inboxId.value));
  if (!device?.restart) return;
  isRestarting.value = true;
  try {
    await device.restart();
    await refreshQr();
  } finally {
    isRestarting.value = false;
  }
};

const handleLogout = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT_CONFIRM'))) {
    return;
  }
  const device = getPrimaryDevice(getWavoipClient(inboxId.value));
  if (!device?.logout) return;
  isLoggingOut.value = true;
  try {
    await device.logout();
    clearQrState();
    await refreshQr();
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
  startSession();
});

onBeforeUnmount(() => {
  stopSession();
  clearQrState();
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.HELP_TEXT')"
    >
      <div v-if="isLoading" class="flex items-center gap-2 text-sm text-n-slate-11">
        <Spinner class="size-4" />
        <span>{{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOADING') }}</span>
      </div>
      <div v-else class="flex flex-col gap-2 text-sm">
        <div>
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WHATSAPP') }}:
          </span>
          <span class="font-medium">{{ statusLabel }}</span>
        </div>
        <div v-if="linkedPhone && whatsAppStatus === 'open'">
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LINKED_PHONE') }}:
          </span>
          <span class="font-medium">{{ linkedPhone }}</span>
        </div>
        <div>
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
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WAKE_UP')"
          :is-loading="isWaking"
          @click="handleWakeUp"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTART')"
          :is-loading="isRestarting"
          @click="handleRestart"
        />
        <NextButton
          sm
          faded
          slate
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.LOGOUT')"
          :is-loading="isLoggingOut"
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

    <SettingsFieldSection
      v-if="showQrSection"
      :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.QR_LABEL')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.SCAN_HINT')"
    >
      <WavoipQrDisplay
        :status="whatsAppStatus"
        :qr-data-url="qrDataUrl"
        :pairing-code="pairingCode"
        :is-loading="isLoading"
        :is-refreshing="isRefreshing"
        :qr-refresh-error="qrRefreshError"
        @refresh="handleRefreshQr"
        @request-pairing-code="handlePairingCode"
      />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_TITLE')"
      :help-text="$t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_HELP')"
    >
      <ul class="list-disc ps-5 text-sm text-n-slate-11 space-y-1">
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_TOGGLE') }}</li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_CALL_EVENT') }}</li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_DEVICE_EVENT') }}</li>
        <li>{{ $t('INBOX_MGMT.WAVOIP_CALL.WEBHOOK.CHECKLIST_URL') }}</li>
      </ul>
    </SettingsFieldSection>
  </div>
</template>
