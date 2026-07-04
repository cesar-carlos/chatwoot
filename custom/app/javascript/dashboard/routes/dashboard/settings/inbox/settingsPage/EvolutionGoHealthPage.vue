<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EvolutionGoQrScanModal from 'customDashboard/components/evolution_go/EvolutionGoQrScanModal.vue';
import { useEvolutionGoHealthConnection } from 'customDashboard/composables/evolution_go/useEvolutionGoHealthConnection';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const STATUS_STYLES = {
  open: { icon: 'i-lucide-circle-check', color: 'text-n-teal-11' },
  connecting: { icon: 'i-lucide-loader-circle', color: 'text-n-amber-11' },
  close: { icon: 'i-lucide-circle-x', color: 'text-n-ruby-11' },
};

const { t } = useI18n();
const qrModalRef = ref(null);

const {
  connectionStatus,
  phoneNumber,
  isLoading,
  isReconnecting,
  isQrModalOpen,
  qrModalFetchFresh,
  staleData,
  isConnected,
  isBusy,
  reconnect,
  onQrConnected,
} = useEvolutionGoHealthConnection(() => props.inbox, { qrModalRef });

const statusStyle = computed(
  () => STATUS_STYLES[connectionStatus.value] || STATUS_STYLES.connecting
);

const statusLabel = computed(() => {
  const key = connectionStatus.value.toUpperCase();
  return t(`INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.${key}`);
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <SettingsFieldSection
      :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.LABEL')"
      :help-text="
        t('INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.HELP_TEXT')
      "
    >
      <div
        v-if="isLoading"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <Spinner class="size-4" />
        {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOADING') }}
      </div>
      <div v-else class="flex flex-col gap-1">
        <div class="flex items-center gap-2">
          <span :class="[statusStyle.icon, statusStyle.color]" class="size-4" />
          <span class="text-sm" :class="statusStyle.color">{{
            statusLabel
          }}</span>
        </div>
        <p v-if="staleData" class="text-xs text-n-amber-11">
          {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.STALE_DATA') }}
        </p>
        <p v-if="phoneNumber" class="text-sm text-n-slate-11">
          {{ phoneNumber }}
        </p>
      </div>
    </SettingsFieldSection>

    <div class="flex flex-wrap gap-3">
      <NextButton
        v-if="!isConnected"
        type="button"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RECONNECT')"
        :is-loading="isReconnecting"
        :disabled="isBusy"
        @click="reconnect"
      />
    </div>

    <EvolutionGoQrScanModal
      v-if="inbox.id"
      ref="qrModalRef"
      v-model="isQrModalOpen"
      :inbox-id="inbox.id"
      :fetch-fresh-qr="qrModalFetchFresh"
      @connected="onQrConnected"
    />
  </div>
</template>
