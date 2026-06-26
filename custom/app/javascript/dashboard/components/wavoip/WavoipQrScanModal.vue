<script setup>
import { ref, watch, toRef, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import WavoipQrDisplay from 'customDashboard/components/wavoip/WavoipQrDisplay.vue';
import { useWavoipQrSession } from 'customDashboard/composables/wavoip/useWavoipQrSession';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import {
  formatWavoipDeviceActionError,
  isWavoipServiceUnavailableError,
} from 'customDashboard/lib/wavoip/wavoipDeviceActionError';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  phoneNumber: {
    type: String,
    default: '',
  },
  fetchFreshQr: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['connected', 'sessionActive']);

const isOpen = defineModel({ type: Boolean, default: false });

const { t } = useI18n();
const { disconnectInbox } = useWavoipConnection();
const dialogRef = ref(null);
let sessionActive = false;

const {
  whatsAppStatus,
  qrDataUrl,
  pairingCode,
  isLoading,
  isRefreshing,
  qrRefreshError,
  hasSdkConnection,
  startSession,
  stopSession,
  requestPairingCode,
  refreshQr,
  handleQrImageError,
  clearQrState,
} = useWavoipQrSession({
  inboxId: toRef(props, 'inboxId'),
  phoneNumber: toRef(props, 'phoneNumber'),
  onConnected: () => {
    emit('connected');
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.CONNECTED'));
    isOpen.value = false;
  },
  onPhoneMismatch: () => {
    useAlert(t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PHONE_MISMATCH'));
  },
});

function cleanupSession() {
  sessionActive = false;
  // Check SDK usage BEFORE clearQrState resets the flag.
  const hadSdkConnection = hasSdkConnection();
  stopSession();
  clearQrState();
  // Only disconnect if this QR session itself opened the SDK connection
  // (e.g. pairing-code path). Avoids disrupting the connection managed
  // by WavoipConnectionHost when the user only scanned a QR.
  if (props.inboxId && hadSdkConnection) {
    disconnectInbox(props.inboxId).catch(() => {});
  }
}

async function openModal() {
  dialogRef.value?.open();
  if (sessionActive) return;

  sessionActive = true;
  try {
    await startSession({ fetchFreshQr: props.fetchFreshQr });
  } catch (error) {
    useAlert(formatWavoipDeviceActionError(error, t));
    if (isWavoipServiceUnavailableError(error) && props.inboxId) {
      disconnectInbox(props.inboxId).catch(() => {});
    }
  }
}

function closeModal() {
  cleanupSession();
  dialogRef.value?.close();
  isOpen.value = false;
}

async function handleRefreshQr() {
  try {
    await refreshQr({ restart: true });
  } catch (error) {
    useAlert(formatWavoipDeviceActionError(error, t));
    if (isWavoipServiceUnavailableError(error) && props.inboxId) {
      disconnectInbox(props.inboxId).catch(() => {});
    }
  }
}

async function handlePairingCode() {
  try {
    await requestPairingCode();
  } catch (error) {
    useAlert(formatWavoipDeviceActionError(error, t));
  }
}

watch(
  isOpen,
  (open, wasOpen) => {
    if (open) {
      nextTick(() => openModal());
    } else if (wasOpen) {
      cleanupSession();
      dialogRef.value?.close();
    }
  },
  { immediate: true }
);

watch(isOpen, open => {
  emit('sessionActive', open);
});

defineExpose({ open: openModal, close: closeModal });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.TITLE')"
    :description="t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.DESCRIPTION')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="isOpen = false"
  >
    <WavoipQrDisplay
      :status="whatsAppStatus"
      :qr-data-url="qrDataUrl"
      :pairing-code="pairingCode"
      :is-loading="isLoading"
      :is-refreshing="isRefreshing"
      :qr-refresh-error="qrRefreshError"
      :show-refresh="false"
      @refresh="handleRefreshQr"
      @request-pairing-code="handlePairingCode"
      @qr-image-error="handleQrImageError"
    />

    <p class="mt-2 text-center text-xs text-n-slate-10">
      {{ t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.EXPIRES_HINT') }}
    </p>

    <template #footer>
      <div class="flex w-full flex-wrap gap-3">
        <Button
          variant="faded"
          color="slate"
          class="min-w-0 flex-1"
          type="button"
          :label="t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.CLOSE')"
          @click="closeModal"
        />
        <Button
          variant="faded"
          color="slate"
          class="min-w-0 flex-1"
          type="button"
          :label="t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PAIRING_CODE')"
          @click="handlePairingCode"
        />
        <Button
          class="min-w-0 flex-1"
          type="button"
          :label="t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.REFRESH')"
          :is-loading="isRefreshing"
          :disabled="isRefreshing"
          @click="handleRefreshQr"
        />
      </div>
    </template>
  </Dialog>
</template>
