<script setup>
import { reactive, watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'next/textarea/TextArea.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import EvolutionHealthPage from 'customDashboard/routes/dashboard/settings/inbox/settingsPage/EvolutionHealthPage.vue';

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const MASKED_SECRET = '••••••••';

const { t } = useI18n();
const store = useStore();
const isSaving = ref(false);

const proxyProtocolOptions = [
  { value: 'http', label: 'HTTP' },
  { value: 'https', label: 'HTTPS' },
  { value: 'socks4', label: 'SOCKS4' },
  { value: 'socks5', label: 'SOCKS5' },
];

function loadState() {
  const config = props.inbox.provider_config || {};

  return {
    groupsIgnore: config.groups_ignore !== false,
    signMsg: config.sign_msg === true,
    signDelimiter: config.sign_delimiter ?? '\n',
    convertMarkdownOutbound: config.convert_markdown_outbound !== false,
    convertMarkdownInbound: config.convert_markdown_inbound !== false,
    markReadOnReply: config.mark_read_on_reply === true,
    notifySendErrorsPrivate: config.notify_send_errors_private !== false,
    syncDeleteToWhatsapp: config.sync_delete_to_whatsapp === true,
    rejectCall: config.reject_call === true,
    readMessages: config.read_messages === true,
    conversationPending: config.conversation_pending === true,
    proxyEnabled: config.proxy_enabled === true,
    proxyHost: config.proxy_host || '',
    proxyPort: config.proxy_port || '',
    proxyProtocol: config.proxy_protocol || 'http',
    proxyUsername: config.proxy_username || '',
    proxyPassword: '',
    ignoreJidsText: (config.ignore_jids || ['@g.us']).join('\n'),
    importContacts: config.import_contacts === true,
    importMessages: config.import_messages === true,
    daysLimitImportMessages: config.days_limit_import_messages ?? 7,
  };
}

const state = reactive(loadState());
const isImporting = ref(false);
const importStatus = ref(null);

watch(
  () => props.inbox.provider_config,
  () => {
    Object.assign(state, loadState());
    const config = props.inbox.provider_config || {};
    importStatus.value = {
      status: config.import_status,
      stats: config.import_stats || {},
      error: config.import_error,
      startedAt: config.import_started_at,
      completedAt: config.import_completed_at,
    };
  },
  { deep: true, immediate: true }
);

function parseIgnoreJids(text) {
  return text
    .split(/[\n,]+/)
    .map(entry => entry.trim())
    .filter(Boolean);
}

function buildProviderConfig() {
  const existing = { ...(props.inbox.provider_config || {}) };
  const ignoreJids = parseIgnoreJids(state.ignoreJidsText);

  if (state.groupsIgnore && !ignoreJids.includes('@g.us')) {
    ignoreJids.push('@g.us');
  }

  const config = {
    ...existing,
    groups_ignore: state.groupsIgnore,
    sign_msg: state.signMsg,
    sign_delimiter: state.signDelimiter,
    convert_markdown_outbound: state.convertMarkdownOutbound,
    convert_markdown_inbound: state.convertMarkdownInbound,
    mark_read_on_reply: state.markReadOnReply,
    notify_send_errors_private: state.notifySendErrorsPrivate,
    sync_delete_to_whatsapp: state.syncDeleteToWhatsapp,
    reject_call: state.rejectCall,
    read_messages: state.readMessages,
    conversation_pending: state.conversationPending,
    proxy_enabled: state.proxyEnabled,
    proxy_host: state.proxyHost,
    proxy_port: state.proxyPort,
    proxy_protocol: state.proxyProtocol,
    proxy_username: state.proxyUsername,
    ignore_jids: ignoreJids,
    import_contacts: state.importContacts,
    import_messages: state.importMessages,
    days_limit_import_messages: Number(state.daysLimitImportMessages) || 7,
  };

  delete config.api_key;
  delete config.reopen_conversation;

  if (state.proxyPassword) {
    config.proxy_password = state.proxyPassword;
  } else if (config.proxy_password === MASKED_SECRET) {
    delete config.proxy_password;
  }

  return config;
}

async function persistSettings({ showSuccessAlert = true } = {}) {
  await store.dispatch('inboxes/updateInbox', {
    id: props.inbox.id,
    formData: false,
    channel: {
      provider_config: buildProviderConfig(),
    },
  });

  if (showSuccessAlert) {
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  }
}

async function saveSettings() {
  if (isSaving.value) return;

  isSaving.value = true;
  try {
    await persistSettings();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.message ||
        t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    isSaving.value = false;
  }
}

async function runImport() {
  if (isImporting.value) return;

  isImporting.value = true;
  try {
    await persistSettings({ showSuccessAlert: false });
    const payload = await store.dispatch(
      'inboxes/evolutionImport',
      props.inbox.id
    );
    importStatus.value = {
      status: payload.import_status,
      stats: payload.import_stats || {},
      error: payload.import_error,
      startedAt: payload.import_started_at,
      completedAt: payload.import_completed_at,
    };
    useAlert(t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.RUN_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.RUN_ERROR')
    );
  } finally {
    isImporting.value = false;
  }
}

function importStatusLabel(status) {
  if (!status) return '';
  const key = status.toUpperCase();
  return t(`INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.STATUS.${key}`, status);
}
</script>

<template>
  <div class="flex flex-col gap-6">
    <EvolutionHealthPage :inbox="inbox" />

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.WHATSAPP_BEHAVIOR_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.groupsIgnore"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.GROUPS_IGNORE.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.GROUPS_IGNORE.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.rejectCall"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.REJECT_CALL.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.REJECT_CALL.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.readMessages"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.READ_MESSAGES.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.READ_MESSAGES.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.conversationPending"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_PENDING.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_PENDING.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.OUTBOUND_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.signMsg"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_MSG.LABEL')"
        :description="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_MSG.DESCRIPTION')"
      />
      <SettingsFieldSection
        v-if="state.signMsg"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_DELIMITER.LABEL')"
        :help-text="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_DELIMITER.DESCRIPTION')
        "
      >
        <Input v-model="state.signDelimiter" />
      </SettingsFieldSection>
      <SettingsToggleSection
        v-model="state.convertMarkdownOutbound"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERT_MARKDOWN_OUTBOUND.LABEL')
        "
        :description="
          t(
            'INBOX_MGMT.EVOLUTION.SETTINGS.CONVERT_MARKDOWN_OUTBOUND.DESCRIPTION'
          )
        "
      />
      <SettingsToggleSection
        v-model="state.convertMarkdownInbound"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERT_MARKDOWN_INBOUND.LABEL')
        "
        :description="
          t(
            'INBOX_MGMT.EVOLUTION.SETTINGS.CONVERT_MARKDOWN_INBOUND.DESCRIPTION'
          )
        "
      />
      <SettingsToggleSection
        v-model="state.markReadOnReply"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.MARK_READ_ON_REPLY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.MARK_READ_ON_REPLY.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.notifySendErrorsPrivate"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.NOTIFY_SEND_ERRORS_PRIVATE.LABEL')
        "
        :description="
          t(
            'INBOX_MGMT.EVOLUTION.SETTINGS.NOTIFY_SEND_ERRORS_PRIVATE.DESCRIPTION'
          )
        "
      />
      <SettingsToggleSection
        v-model="state.syncDeleteToWhatsapp"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_DELETE_TO_WHATSAPP.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_DELETE_TO_WHATSAPP.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.importContacts"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.CONTACTS.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.CONTACTS.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.importMessages"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.MESSAGES.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.MESSAGES.DESCRIPTION')
        "
      />
      <SettingsFieldSection
        v-if="state.importMessages"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.DAYS_LIMIT.LABEL')"
        :help-text="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.DAYS_LIMIT.DESCRIPTION')
        "
      >
        <Input
          v-model="state.daysLimitImportMessages"
          type="number"
          min="1"
          max="365"
        />
      </SettingsFieldSection>
      <div
        v-if="importStatus?.status"
        class="text-sm text-n-slate-11 space-y-1"
      >
        <p>
          {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.STATUS_LABEL') }}:
          {{ importStatusLabel(importStatus.status) }}
        </p>
        <p v-if="importStatus.stats?.contacts_imported">
          {{
            t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.STATS_CONTACTS', {
              count: importStatus.stats.contacts_imported,
            })
          }}
        </p>
        <p v-if="importStatus.stats?.messages_imported">
          {{
            t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.STATS_MESSAGES', {
              count: importStatus.stats.messages_imported,
            })
          }}
        </p>
        <p v-if="importStatus.error" class="text-n-ruby-11">
          {{ importStatus.error }}
        </p>
      </div>
      <div class="flex justify-end">
        <NextButton
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.RUN')"
          :is-loading="isImporting"
          :disabled="!state.importContacts && !state.importMessages"
          @click="runImport"
        />
      </div>
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.FILTERS_SECTION')"
    >
      <SettingsFieldSection
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_JIDS.LABEL')"
        :help-text="t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_JIDS.DESCRIPTION')"
      >
        <TextArea
          v-model="state.ignoreJidsText"
          :placeholder="
            t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_JIDS.PLACEHOLDER')
          "
          auto-height
          resize
          class="w-full [&>div]:!bg-transparent [&>div]:!border-none [&>div]:!border-0 [&>div]:px-0 [&>div]:pb-0 [&>div]:pt-0"
        />
      </SettingsFieldSection>
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.proxyEnabled"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.ENABLED.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.ENABLED.DESCRIPTION')
        "
      />
      <div v-if="state.proxyEnabled" class="space-y-4">
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.HOST.LABEL')"
        >
          <Input v-model="state.proxyHost" />
        </SettingsFieldSection>
        <div class="grid grid-cols-2 gap-4">
          <SettingsFieldSection
            :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PORT.LABEL')"
          >
            <Input v-model="state.proxyPort" />
          </SettingsFieldSection>
          <SettingsFieldSection
            :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PROTOCOL.LABEL')"
          >
            <SelectInput
              v-model="state.proxyProtocol"
              :options="proxyProtocolOptions"
            />
          </SettingsFieldSection>
        </div>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.USERNAME.LABEL')"
        >
          <Input v-model="state.proxyUsername" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PASSWORD.LABEL')"
          :help-text="
            t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PASSWORD.DESCRIPTION')
          "
        >
          <Input v-model="state.proxyPassword" type="password" />
        </SettingsFieldSection>
      </div>
    </SettingsAccordion>

    <div class="flex justify-end">
      <NextButton
        :label="t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
        :is-loading="isSaving"
        @click="saveSettings"
      />
    </div>
  </div>
</template>
