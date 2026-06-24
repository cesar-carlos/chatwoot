<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  status: {
    type: String,
    default: '',
  },
  qrDataUrl: {
    type: String,
    default: '',
  },
  pairingCode: {
    type: String,
    default: '',
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  isRefreshing: {
    type: Boolean,
    default: false,
  },
  qrRefreshError: {
    type: Boolean,
    default: false,
  },
  showRefresh: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['refresh', 'requestPairingCode']);

const { t } = useI18n();

const statusKey = computed(() => (props.status || 'connecting').toUpperCase());

const statusLabel = computed(() =>
  t(`INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.${statusKey.value}`, statusKey.value)
);

const showQr = computed(() => Boolean(props.qrDataUrl));

const showLoading = computed(
  () =>
    (props.isLoading || props.isRefreshing) &&
    !showQr.value &&
    !props.pairingCode
);

const showQrError = computed(
  () =>
    props.showRefresh &&
    !showQr.value &&
    !showLoading.value &&
    !props.pairingCode &&
    (props.qrRefreshError || props.status === 'close')
);
</script>

<template>
  <div class="flex flex-col items-center gap-4 text-center">
    <div class="flex items-center gap-2 text-sm text-n-slate-11">
      <span
        class="size-2 rounded-full"
        :class="
          status === 'open'
            ? 'bg-n-teal-9'
            : status === 'close'
              ? 'bg-n-ruby-9'
              : 'bg-n-amber-9'
        "
      />
      {{
        $t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.STATUS', {
          status: statusLabel,
        })
      }}
    </div>

    <div
      v-if="showQr"
      class="p-4 rounded-2xl bg-white border border-n-weak shadow-sm"
    >
      <img
        :src="qrDataUrl"
        :alt="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.QR_LABEL')"
        class="w-56 h-56 object-contain"
      />
    </div>

    <div
      v-else-if="showLoading"
      class="flex flex-col items-center gap-2 py-8 text-sm text-n-slate-11"
    >
      <Spinner class="size-6" />
      {{ $t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.LOADING') }}
    </div>

    <div
      v-else-if="showQrError"
      class="flex flex-col items-center gap-3 py-8 text-sm text-n-slate-11"
    >
      <p>{{ $t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.REFRESH_ERROR') }}</p>
      <NextButton
        sm
        faded
        slate
        :label="$t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.REFRESH')"
        :is-loading="isRefreshing"
        @click="emit('refresh')"
      />
    </div>

    <p v-if="showQr" class="text-xs text-n-slate-11 max-w-sm">
      {{ $t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.SCAN_HINT') }}
    </p>

    <p
      v-if="pairingCode"
      class="text-sm font-medium text-n-slate-12 break-all max-w-full px-2"
    >
      {{
        $t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.PAIRING_CODE', {
          code: pairingCode,
        })
      }}
    </p>

    <p v-if="pairingCode" class="text-xs text-n-slate-11 max-w-sm">
      {{ $t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.PAIRING_HINT') }}
    </p>

    <div v-if="showRefresh" class="flex flex-wrap justify-center gap-2">
      <NextButton
        sm
        faded
        slate
        :label="$t('INBOX_MGMT.WAVOIP_CALL.QR_MODAL.REFRESH')"
        :is-loading="isRefreshing"
        @click="emit('refresh')"
      />
      <NextButton
        sm
        faded
        slate
        :label="$t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.PAIRING_CODE')"
        @click="emit('requestPairingCode')"
      />
    </div>
  </div>
</template>
