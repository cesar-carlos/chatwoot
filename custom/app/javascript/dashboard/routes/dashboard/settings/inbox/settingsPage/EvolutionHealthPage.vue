<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EvolutionQrScanModal from 'customDashboard/components/evolution/EvolutionQrScanModal.vue';
import { useEvolutionHealthConnection } from 'customDashboard/composables/evolution/useEvolutionHealthConnection';

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
const confirmDialog = ref(null);
const qrModalRef = ref(null);

const {
  connectionStatus,
  phoneNumber,
  isLoading,
  isLoggingOut,
  isRestarting,
  isQrModalOpen,
  qrModalFetchFresh,
  staleData,
  confirmTitle,
  confirmDescription,
  isConnected,
  isBusy,
  reconnect,
  restart,
  logout,
  onQrConnected,
} = useEvolutionHealthConnection(() => props.inbox, { qrModalRef });

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
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      v-if="phoneNumber && isConnected"
      :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.PHONE_NUMBER.LABEL')"
      :help-text="
        t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.PHONE_NUMBER.HELP_TEXT')
      "
    >
      <woot-code :script="phoneNumber" lang="html" />
    </SettingsFieldSection>

    <div class="flex flex-wrap gap-3">
      <NextButton
        v-if="!isConnected"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RECONNECT')"
        :disabled="isBusy"
        @click="reconnect"
      />
      <NextButton
        faded
        slate
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.RESTART')"
        :is-loading="isRestarting"
        :disabled="isBusy"
        @click="restart(confirmDialog)"
      />
      <NextButton
        faded
        ruby
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT')"
        :is-loading="isLoggingOut"
        :disabled="isBusy"
        @click="logout(confirmDialog)"
      />
    </div>

    <EvolutionQrScanModal
      ref="qrModalRef"
      v-model="isQrModalOpen"
      :inbox-id="inbox.id"
      :fetch-fresh-qr="qrModalFetchFresh"
      cable-managed-externally
      @connected="onQrConnected"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="confirmTitle"
      :description="confirmDescription"
    />
  </div>
</template>
