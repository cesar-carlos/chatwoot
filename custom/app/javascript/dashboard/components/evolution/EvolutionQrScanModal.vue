<script setup>
import { computed, ref, watch, toRef, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useEvolutionQrSession } from 'customDashboard/composables/evolution/useEvolutionQrSession';
import { subscribeEvolutionConnection } from 'customDashboard/composables/evolution/useEvolutionConnectionCable';

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
} = useEvolutionQrSession({
  inboxId: toRef(props, 'inboxId'),
  store,
  onConnected: () => {
    emit('connected');
    useAlert(t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.CONNECTED'));
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
const showLoading = computed(
  () =>
    (isLoading.value || isRefreshing.value) &&
    !showQr.value &&
    !pairingCode.value
);
const showQrError = computed(
  () =>
    !showQr.value &&
    !showLoading.value &&
    !pairingCode.value &&
    (qrRefreshError.value || connectionStatus.value === 'close')
);

function cleanupSession() {
  sessionActive = false;
  stopSession();
  unsubscribeCable?.();
  unsubscribeCable = null;
}

function openModal() {
  dialogRef.value?.open();
  if (sessionActive) return;

  sessionActive = true;
  unsubscribeCable = subscribeEvolutionConnection(props.inboxId, applyPayload, {
    store,
  });
  startSession({ fetchFreshQr: props.fetchFreshQr });
}

function closeModal() {
  cleanupSession();
  dialogRef.value?.close();
  isOpen.value = false;
}

async function handleRefreshQr() {
  try {
    await requestNewQr();
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.REFRESH_ERROR')
    );
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
          alt="WhatsApp QR Code"
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
          @click="handleRefreshQr"
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

      <p class="text-xs text-n-slate-10">
        {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.QR_MODAL.EXPIRES_HINT') }}
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
          @click="handleRefreshQr"
        />
      </div>
    </template>
  </Dialog>
</template>
