<script setup>
import { reactive, watch, ref, computed } from 'vue';
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
import SingleHistoryAutomationWarning from 'dashboard/routes/dashboard/settings/inbox/components/SingleHistoryAutomationWarning.vue';

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
    convertMarkdownOutbound: config.convert_markdown_outbound !== false,
    convertMarkdownInbound: config.convert_markdown_inbound !== false,
    sendRandomDelay: config.send_random_delay !== false,
    markReadOnReply: config.mark_read_on_reply === true,
    notifySendErrorsPrivate: config.notify_send_errors_private !== false,
    syncDeleteToWhatsapp: config.sync_delete_to_whatsapp === true,
    mergeBrazilContacts: config.merge_brazil_contacts !== false,
    ignoreSurveyLinks: config.ignore_survey_links !== false,
    ignoreFromMeEcho: config.ignore_from_me_echo === true,
    ignoreStatusBroadcast: config.ignore_status_broadcast !== false,
    sendTemplatesAsText: config.send_templates_as_text !== false,
    formatGroupMessages: config.format_group_messages === true,
    readStatus: config.read_status === true,
    syncFullHistory: config.sync_full_history === true,
    alwaysOnline: config.always_online === true,
    msgCall: config.msg_call || '',
    importOnConnect: config.import_on_connect !== false,
    syncLostMessages: config.sync_lost_messages === true,
    rejectCall: config.reject_call === true,
    readMessages: config.read_messages === true,
    conversationPending: config.conversation_pending === true,
    lockToSingleConversation: props.inbox.lock_to_single_conversation !== false,
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
const isRestartingProxy = ref(false);
const importStatus = ref(null);

const settingsSyncError = computed(
  () => props.inbox.provider_config?.settings_sync_error || ''
);

const showPendingRequiresReopenWarning = computed(
  () => state.conversationPending && !state.lockToSingleConversation
);

const canSaveConversationSettings = computed(
  () => !state.conversationPending || state.lockToSingleConversation
);

watch(
  () => props.inbox.lock_to_single_conversation,
  value => {
    state.lockToSingleConversation = value !== false;
  }
);

watch(
  () => state.lockToSingleConversation,
  enabled => {
    if (!enabled) state.conversationPending = false;
  }
);

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
  } else if (!state.groupsIgnore) {
    const groupIndex = ignoreJids.indexOf('@g.us');
    if (groupIndex >= 0) ignoreJids.splice(groupIndex, 1);
  }

  const config = {
    ...existing,
    groups_ignore: state.groupsIgnore,
    sign_msg: state.signMsg,
    convert_markdown_outbound: state.convertMarkdownOutbound,
    convert_markdown_inbound: state.convertMarkdownInbound,
    send_random_delay: state.sendRandomDelay,
    mark_read_on_reply: state.markReadOnReply,
    notify_send_errors_private: state.notifySendErrorsPrivate,
    sync_delete_to_whatsapp: state.syncDeleteToWhatsapp,
    merge_brazil_contacts: state.mergeBrazilContacts,
    ignore_survey_links: state.ignoreSurveyLinks,
    ignore_from_me_echo: state.ignoreFromMeEcho,
    ignore_status_broadcast: state.ignoreStatusBroadcast,
    send_templates_as_text: state.sendTemplatesAsText,
    format_group_messages: state.formatGroupMessages,
    reject_call: state.rejectCall,
    read_messages: state.readMessages,
    read_status: state.readStatus,
    sync_full_history: state.syncFullHistory,
    always_online: state.alwaysOnline,
    msg_call: state.msgCall,
    conversation_pending: state.conversationPending,
    proxy_enabled: state.proxyEnabled,
    proxy_host: state.proxyHost,
    proxy_port: state.proxyPort,
    proxy_protocol: state.proxyProtocol,
    proxy_username: state.proxyUsername,
    ignore_jids: ignoreJids,
    import_contacts: state.importContacts,
    import_messages: state.importMessages,
    import_on_connect: state.importOnConnect,
    sync_lost_messages: state.syncLostMessages,
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
    lock_to_single_conversation: state.lockToSingleConversation,
    channel: {
      provider_config: buildProviderConfig(),
    },
  });

  const updatedInbox = store.getters['inboxes/getInbox'](props.inbox.id);
  const syncError = updatedInbox?.provider_config?.settings_sync_error;
  if (syncError) {
    useAlert(syncError);
    return;
  }

  if (showSuccessAlert) {
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  }
}

async function saveSettings() {
  if (isSaving.value) return;

  if (!canSaveConversationSettings.value) {
    useAlert(
      t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_PENDING_REQUIRES_REOPEN')
    );
    return;
  }

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

async function restartAfterProxyChange() {
  if (isRestartingProxy.value) return;

  isRestartingProxy.value = true;
  try {
    await persistSettings({ showSuccessAlert: false });
    await store.dispatch('inboxes/evolutionRestart', props.inbox.id);
    useAlert(t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.RESTART_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        error?.message ||
        t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.RESTART_ERROR')
    );
  } finally {
    isRestartingProxy.value = false;
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

    <p
      v-if="settingsSyncError"
      class="text-sm text-n-ruby-11 rounded-lg border border-n-ruby-6 bg-n-ruby-2 px-4 py-3"
    >
      {{
        t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_ERROR', {
          error: settingsSyncError,
        })
      }}
    </p>

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
      <p
        v-if="!state.groupsIgnore"
        class="text-sm text-n-amber-11 rounded-lg border border-n-amber-6 bg-n-amber-2 px-4 py-3 mb-4"
      >
        {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.GROUPS_IGNORE.EXPERIMENTAL_WARNING') }}
      </p>
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
      <SettingsToggleSection
        v-model="state.readStatus"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.READ_STATUS.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.READ_STATUS.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.syncFullHistory"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_FULL_HISTORY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_FULL_HISTORY.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.alwaysOnline"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.ALWAYS_ONLINE.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.ALWAYS_ONLINE.DESCRIPTION')
        "
      />
      <SettingsFieldSection
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.MSG_CALL.LABEL')"
        :help-text="t('INBOX_MGMT.EVOLUTION.SETTINGS.MSG_CALL.DESCRIPTION')"
      >
        <Input v-model="state.msgCall" />
      </SettingsFieldSection>
      <SettingsToggleSection
        v-model="state.formatGroupMessages"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.FORMAT_GROUP_MESSAGES.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.FORMAT_GROUP_MESSAGES.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.lockToSingleConversation"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.REOPEN_CONVERSATION.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.REOPEN_CONVERSATION.DESCRIPTION')
        "
      />
      <SingleHistoryAutomationWarning
        :inbox-id="inbox.id"
        :lock-to-single-conversation="state.lockToSingleConversation"
      />
      <SettingsToggleSection
        v-model="state.conversationPending"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_PENDING.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_PENDING.DESCRIPTION')
        "
      />
      <p v-if="showPendingRequiresReopenWarning" class="text-sm text-n-ruby-11">
        {{
          t(
            'INBOX_MGMT.EVOLUTION.SETTINGS.CONVERSATION_PENDING_REQUIRES_REOPEN'
          )
        }}
      </p>
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.OUTBOUND_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.signMsg"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_MSG.LABEL')"
        :description="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_MSG.DESCRIPTION')"
      />
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
      <p class="text-sm text-n-slate-11">
        {{
          t(
            'INBOX_MGMT.EVOLUTION.SETTINGS.OPERATIONAL_NOTES.PARTIAL_ATTACHMENTS'
          )
        }}
      </p>
      <SettingsToggleSection
        v-model="state.syncDeleteToWhatsapp"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_DELETE_TO_WHATSAPP.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_DELETE_TO_WHATSAPP.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.sendTemplatesAsText"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_TEMPLATES_AS_TEXT.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_TEMPLATES_AS_TEXT.DESCRIPTION')
        "
      />
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.OPERATIONAL_NOTES.TEMPLATES') }}
      </p>
      <SettingsToggleSection
        v-model="state.sendRandomDelay"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_RANDOM_DELAY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_RANDOM_DELAY.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.mergeBrazilContacts"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.MERGE_BRAZIL_CONTACTS.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.MERGE_BRAZIL_CONTACTS.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT_SECTION')"
    >
      <p
        v-if="state.importContacts || state.importMessages"
        class="text-sm text-n-amber-11"
      >
        {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.AUTO_ON_CONNECT_WARNING') }}
      </p>
      <SettingsToggleSection
        v-model="state.importOnConnect"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.ON_CONNECT.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.ON_CONNECT.DESCRIPTION')
        "
      />
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
      <SettingsToggleSection
        v-model="state.ignoreSurveyLinks"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_SURVEY_LINKS.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_SURVEY_LINKS.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.ignoreFromMeEcho"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_FROM_ME_ECHO.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_FROM_ME_ECHO.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.ignoreStatusBroadcast"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_STATUS_BROADCAST.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_STATUS_BROADCAST.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.syncLostMessages"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_LOST_MESSAGES.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_LOST_MESSAGES.DESCRIPTION')
        "
      />
      <p class="text-sm text-n-slate-11">
        {{
          t('INBOX_MGMT.EVOLUTION.SETTINGS.OPERATIONAL_NOTES.RECONCILIATION')
        }}
      </p>
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
        <p class="text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.RESTART_HINT') }}
        </p>
        <div class="flex justify-end">
          <NextButton
            :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.RESTART')"
            :is-loading="isRestartingProxy"
            faded
            @click="restartAfterProxyChange"
          />
        </div>
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
