<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { getPrimaryDevice } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import { exportWavoipDiagnostics } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';
import { unwrapWavoipSdkResult } from 'customDashboard/lib/wavoip/wavoipSdkResult';
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
const { connectForInbox, wakeUpInboxDevice } = useWavoipConnection();
const qrCode = ref('');
const pairingCode = ref('');
const isLoading = ref(false);
const isWaking = ref(false);
const isRestarting = ref(false);
const isLoggingOut = ref(false);
let deviceUnsubscribers = [];

const inboxId = computed(() => props.inbox.id);

const whatsAppStatus = computed(() => {
  const entry = getWavoipDeviceStatus(inboxId.value);
  return entry.whatsAppStatus.value;
});
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

const clearDeviceListeners = () => {
  deviceUnsubscribers.forEach(unsub => {
    try {
      unsub();
    } catch (_) {
      /* noop */
    }
  });
  deviceUnsubscribers = [];
};

const wireDeviceListeners = () => {
  clearDeviceListeners();
  const client = getWavoipClient(inboxId.value);
  const device = getPrimaryDevice(client);
  if (!device?.on) return;

  deviceUnsubscribers.push(
    device.on('qrCodeChanged', code => {
      qrCode.value = code || '';
    })
  );
  deviceUnsubscribers.push(
    device.on('contactChanged', contact => {
      if (contact?.phone && contact.phone !== props.inbox.phone_number) {
        useAlert(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PHONE_MISMATCH'));
      }
    })
  );
};

const loadDevice = async () => {
  isLoading.value = true;
  try {
    await connectForInbox(inboxId.value);
    wireDeviceListeners();
  } finally {
    isLoading.value = false;
  }
};

watch(inboxId, () => {
  qrCode.value = '';
  pairingCode.value = '';
  loadDevice();
});

const handleWakeUp = async () => {
  isWaking.value = true;
  try {
    await wakeUpInboxDevice(inboxId.value);
  } finally {
    isWaking.value = false;
  }
};

const handlePairingCode = async () => {
  const client = getWavoipClient(inboxId.value);
  const device = getPrimaryDevice(client);
  if (!device?.pairingCode || !props.inbox.phone_number) return;

  const raw = await device.pairingCode(props.inbox.phone_number);
  const { pairingCode: code, err } = unwrapWavoipSdkResult(raw, 'pairingCode');
  if (err) {
    useAlert(typeof err === 'string' ? err : err?.message || 'Pairing failed');
    return;
  }
  pairingCode.value = code || '';
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
    qrCode.value = '';
    pairingCode.value = '';
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
  loadDevice();
});

onBeforeUnmount(() => {
  clearDeviceListeners();
  qrCode.value = '';
  pairingCode.value = '';
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
          :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PAIRING_CODE')"
          @click="handlePairingCode"
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
      v-if="qrCode"
      :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.QR_LABEL')"
    >
      <woot-code :script="qrCode" lang="html" />
    </SettingsFieldSection>

    <SettingsFieldSection
      v-if="pairingCode"
      :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PAIRING_CODE_LABEL')"
    >
      <woot-code :script="pairingCode" lang="html" />
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
