<script setup>
import { computed, ref, watch, toRef, nextTick, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useEvolutionGoQrSession } from 'customDashboard/composables/evolution_go/useEvolutionGoQrSession';
import { subscribeEvolutionGoConnection } from 'customDashboard/lib/evolution_go/evolutionGoCableRegistry';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  fetchFreshQr: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['connected', 'sessionActive']);

const isOpen = defineModel({ type: Boolean, default: false });

const { t } = useI18n();
const store = useStore();
const dialogRef = ref(null);
let unsubscribeCable = null;
let sessionActive = false;

const {
  connectionStatus,
  qrcodeBase64,
  pairingCode,
  isLoading,
  isRefreshing,
  qrRefreshError,
  requestNewQr,
  startSession,
  stopSession,
  applyPayload,
} = useEvolutionGoQrSession({
  inboxId: toRef(props, 'inboxId'),
  store,
  onConnected: () => {
    emit('connected');
    isOpen.value = false;
  },
});

const statusKey = computed(
  () => connectionStatus.value?.toUpperCase() || 'CONNECTING'
);

const statusLabel = computed(() =>
  t(`INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.${statusKey.value}`)
);

const showQr = computed(() => Boolean(qrcodeBase64.value));
const closeWithoutQrTimedOut = ref(false);
let closeWithoutQrTimer = null;

const showLoading = computed(
  () =>
    !showQr.value &&
    !pairingCode.value &&
    !qrRefreshError.value &&
    !closeWithoutQrTimedOut.value &&
    (isLoading.value ||
      isRefreshing.value ||
      connectionStatus.value === 'connecting')
);
const showQrError = computed(
  () =>
    !showQr.value &&
    !showLoading.value &&
    !pairingCode.value &&
    (qrRefreshError.value || closeWithoutQrTimedOut.value)
);

function clearCloseWithoutQrTimer() {
  if (closeWithoutQrTimer) {
    clearTimeout(closeWithoutQrTimer);
    closeWithoutQrTimer = null;
  }
}

function scheduleCloseWithoutQrTimeout(status) {
  clearCloseWithoutQrTimer();
  closeWithoutQrTimedOut.value = false;

  if (status === 'close' && !qrcodeBase64.value && !pairingCode.value) {
    closeWithoutQrTimer = setTimeout(() => {
      closeWithoutQrTimedOut.value = true;
    }, 5000);
  }
}

function cleanupSession() {
  sessionActive = false;
  clearCloseWithoutQrTimer();
  closeWithoutQrTimedOut.value = false;
  stopSession();
  unsubscribeCable?.();
  unsubscribeCable = null;
}

function openModal() {
  dialogRef.value?.open();
  if (sessionActive) return;

  sessionActive = true;
  unsubscribeCable = subscribeEvolutionGoConnection(
    props.inboxId,
    applyPayload,
    { store }
  );
  startSession({ fetchFreshQr: props.fetchFreshQr });
}

function closeModal() {
  cleanupSession();
  dialogRef.value?.close();
  isOpen.value = false;
}

watch(
  [connectionStatus, qrcodeBase64, pairingCode],
  ([status, qr, code]) => {
    if (qr || code) {
      clearCloseWithoutQrTimer();
      closeWithoutQrTimedOut.value = false;
      return;
    }
    scheduleCloseWithoutQrTimeout(status);
  },
  { immediate: true }
);

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

onUnmounted(() => {
  cleanupSession();
});

defineExpose({ open: openModal, close: closeModal, applyPayload });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.TITLE')"
    :description="t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.DESCRIPTION')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="isOpen = false"
  >
    <div class="flex flex-col items-center gap-4 text-center">
      <div class="flex items-center gap-2 text-sm text-n-slate-11">
        <span
          class="size-2 rounded-full"
          :class="
            connectionStatus === 'open'
              ? 'bg-n-teal-9'
              : connectionStatus === 'close'
                ? 'bg-n-ruby-9'
                : 'bg-n-amber-9'
          "
        />
        {{
          t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.STATUS', {
            status: statusLabel,
          })
        }}
      </div>

      <div
        v-if="showQr"
        class="p-4 rounded-2xl bg-white border border-n-weak shadow-sm"
      >
        <img
          :src="qrcodeBase64"
          :alt="t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.QR_ALT')"
          class="w-56 h-56 object-contain"
        />
      </div>

      <div
        v-else-if="showLoading"
        class="flex flex-col items-center gap-2 py-8 text-sm text-n-slate-11"
      >
        <Spinner class="size-6" />
        {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.LOADING') }}
      </div>

      <div
        v-else-if="showQrError"
        class="flex flex-col items-center gap-3 py-8 text-sm text-n-slate-11"
      >
        <p>{{ t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.REFRESH_ERROR') }}</p>
        <Button
          type="button"
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.REFRESH')"
          :is-loading="isRefreshing"
          :disabled="isRefreshing"
          @click="requestNewQr"
        />
      </div>

      <p
        v-if="pairingCode"
        class="text-sm font-medium text-n-slate-12 break-all max-w-full px-2"
      >
        {{
          t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.PAIRING_CODE', {
            code: pairingCode,
          })
        }}
      </p>
    </div>

    <template #footer>
      <div class="flex w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          class="w-full"
          type="button"
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.CLOSE')"
          @click="closeModal"
        />
        <Button
          class="w-full"
          type="button"
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.REFRESH')"
          :is-loading="isRefreshing"
          :disabled="isRefreshing"
          @click="requestNewQr"
        />
      </div>
    </template>
  </Dialog>
</template>
