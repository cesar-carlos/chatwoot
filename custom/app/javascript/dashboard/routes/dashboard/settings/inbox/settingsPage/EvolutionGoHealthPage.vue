<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
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
const confirmDialog = ref(null);
const qrModalRef = ref(null);
const diagnostics = ref(null);
const isDiagnosticsLoading = ref(false);
const isTestingWebhook = ref(false);

const {
  connectionStatus,
  phoneNumber,
  isLoading,
  isReconnecting,
  isLoggingOut,
  isSyncingWebhook,
  isQrModalOpen,
  qrModalFetchFresh,
  staleData,
  confirmTitle,
  confirmDescription,
  isConnected,
  isBusy,
  reconnect,
  logout,
  syncWebhook,
  onQrConnected,
} = useEvolutionGoHealthConnection(() => props.inbox, { qrModalRef });

const statusStyle = computed(
  () => STATUS_STYLES[connectionStatus.value] || STATUS_STYLES.connecting
);

const statusLabel = computed(() => {
  const key = connectionStatus.value.toUpperCase();
  return t(`INBOX_MGMT.EVOLUTION.SETTINGS.CONNECTION_STATUS.${key}`);
});

const mutationStats = computed(() => diagnostics.value?.mutation_stats || {});

async function loadDiagnostics() {
  if (!props.inbox?.id) return;

  isDiagnosticsLoading.value = true;
  try {
    const { data } = await InboxesAPI.getEvolutionGoDiagnostics(props.inbox.id);
    diagnostics.value = data;
  } catch {
    diagnostics.value = null;
  } finally {
    isDiagnosticsLoading.value = false;
  }
}

async function testWebhook() {
  if (!props.inbox?.id || isTestingWebhook.value) return;

  isTestingWebhook.value = true;
  try {
    await InboxesAPI.postEvolutionGoTestWebhook(props.inbox.id);
    useAlert(t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.TEST_WEBHOOK_SUCCESS'));
    await loadDiagnostics();
  } catch {
    useAlert(t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.TEST_WEBHOOK_ERROR'));
  } finally {
    isTestingWebhook.value = false;
  }
}

async function handleSyncWebhook() {
  await syncWebhook();
  await loadDiagnostics();
}

onMounted(loadDiagnostics);
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
      <NextButton
        v-if="isConnected"
        faded
        ruby
        type="button"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.LOGOUT')"
        :is-loading="isLoggingOut"
        :disabled="isBusy"
        @click="logout(confirmDialog)"
      />
    </div>

    <SettingsFieldSection
      :label="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.TITLE')"
    >
      <div
        v-if="isDiagnosticsLoading"
        class="flex items-center gap-2 text-sm text-n-slate-11"
      >
        <Spinner class="size-4" />
        {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.LOADING') }}
      </div>
      <div v-else-if="diagnostics" class="text-sm text-n-slate-11 space-y-2">
        <p v-if="diagnostics.webhook_url">
          <span class="font-medium">
            {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.WEBHOOK_URL') }}:
          </span>
          {{ diagnostics.webhook_url }}
        </p>
        <p v-if="diagnostics.webhook_subscribe?.length">
          <span class="font-medium">
            {{
              t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.WEBHOOK_SUBSCRIBE')
            }}:
          </span>
          {{ diagnostics.webhook_subscribe.join(', ') }}
        </p>
        <p v-if="diagnostics.import_status">
          <span class="font-medium">
            {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.IMPORT_STATUS') }}:
          </span>
          {{ diagnostics.import_status }}
        </p>
        <p v-if="diagnostics.settings_sync_error" class="text-n-ruby-11">
          {{ diagnostics.settings_sync_error }}
        </p>
        <p v-if="diagnostics.import_error" class="text-n-ruby-11">
          {{ diagnostics.import_error }}
        </p>
        <p v-if="diagnostics.instance_info?.name || diagnostics.instance_info?.Name">
          <span class="font-medium">
            {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.INSTANCE_NAME') }}:
          </span>
          {{ diagnostics.instance_info.name || diagnostics.instance_info.Name }}
        </p>
        <p v-if="mutationStats.inbound_delete_skipped">
          {{
            t(
              'INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.INBOUND_DELETE_SKIPPED',
              { count: mutationStats.inbound_delete_skipped }
            )
          }}
        </p>
        <p v-if="mutationStats.inbound_edit_skipped">
          {{
            t(
              'INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.INBOUND_EDIT_SKIPPED',
              { count: mutationStats.inbound_edit_skipped }
            )
          }}
        </p>
        <div class="flex flex-wrap gap-2">
          <NextButton
            variant="faded"
            :label="
              t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.TEST_WEBHOOK')
            "
            :is-loading="isTestingWebhook"
            :disabled="isBusy"
            @click="testWebhook"
          />
          <NextButton
            variant="faded"
            :label="
              t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.DIAGNOSTICS.SYNC_WEBHOOK')
            "
            :is-loading="isSyncingWebhook"
            :disabled="isBusy"
            @click="handleSyncWebhook"
          />
        </div>
      </div>
    </SettingsFieldSection>

    <EvolutionGoQrScanModal
      v-if="inbox.id"
      ref="qrModalRef"
      v-model="isQrModalOpen"
      :inbox-id="inbox.id"
      :fetch-fresh-qr="qrModalFetchFresh"
      @connected="onQrConnected"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="confirmTitle"
      :description="confirmDescription"
    />
  </div>
</template>
