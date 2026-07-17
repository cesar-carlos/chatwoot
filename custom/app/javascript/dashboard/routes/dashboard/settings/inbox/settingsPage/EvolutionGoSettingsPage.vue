<script setup>
import { reactive, watch, ref, computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TextArea from 'next/textarea/TextArea.vue';
import EvolutionGoHealthPage from 'customDashboard/routes/dashboard/settings/inbox/settingsPage/EvolutionGoHealthPage.vue';
import { useEvolutionGoImportStatus } from 'customDashboard/composables/evolution_go/useEvolutionGoImportStatus';

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
const isRemovingProxy = ref(false);
const isImporting = ref(false);
const isRefreshingContacts = ref(false);
const showImportConfirmModal = ref(false);
const importStatus = ref(null);

const inboxRef = toRef(props, 'inbox');
useEvolutionGoImportStatus(inboxRef);

function loadState() {
  const config = props.inbox.provider_config || {};

  return {
    groupsIgnore: config.ignore_groups !== false,
    signMsg: config.sign_msg === true,
    convertMarkdownOutbound: config.convert_markdown_outbound !== false,
    convertMarkdownInbound: config.convert_markdown_inbound !== false,
    sendRandomDelay: config.send_random_delay === true,
    markReadOnReply: config.mark_read_on_reply === true,
    markReadOnOpen: config.mark_read_on_open !== false,
    notifySendErrorsPrivate: config.notify_send_errors_private !== false,
    sendTemplatesAsText: config.send_templates_as_text !== false,
    ignoreFromMeEcho: config.ignore_from_me_echo !== false,
    rejectCall: config.reject_call === true,
    readMessages: config.read_messages === true,
    alwaysOnline: config.always_online === true,
    ignoreStatus: config.ignore_status !== false,
    msgCall: config.msg_call || '',
    mergeBrazilContacts: config.merge_brazil_contacts !== false,
    importOnConnect: config.import_on_connect === true,
    importContacts: config.import_contacts === true,
    importMessages: config.import_messages === true,
    // Stored as days_limit_import_messages for backward compatibility; value is
    // the Evolution Go history-sync `count` (messages per chat), not days.
    daysLimitImportMessages: config.days_limit_import_messages || 100,
    markInboundDeleted: config.mark_inbound_deleted !== false,
    markInboundEdited: config.mark_inbound_edited !== false,
    syncDeleteToWhatsapp: config.sync_delete_to_whatsapp === true,
    syncEditToWhatsapp: config.sync_edit_to_whatsapp === true,
    proxyEnabled: config.proxy_enabled === true,
    proxyHost: config.proxy_host || '',
    proxyPort: config.proxy_port || '',
    proxyUsername: config.proxy_username || '',
    proxyPassword: '',
  };
}

const state = reactive(loadState());

const settingsSyncError = computed(
  () => props.inbox.provider_config?.settings_sync_error || ''
);

const hasExistingProxy = computed(() =>
  Boolean(props.inbox.provider_config?.proxy_host)
);

const proxyEditDisabled = computed(
  () =>
    Boolean(props.inbox.provider_config?.instance_id) && !hasExistingProxy.value
);

watch(
  () => props.inbox.id,
  () => {
    Object.assign(state, loadState());
  },
  { immediate: true }
);

watch(
  () => props.inbox.provider_config,
  () => {
    const config = props.inbox.provider_config || {};
    importStatus.value = {
      status: config.import_status,
      stats: config.import_stats || {},
      error: config.import_error,
      startedAt: config.import_started_at,
      completedAt: config.import_completed_at,
    };
  },
  { immediate: true, deep: true }
);

function buildProviderConfig() {
  const config = {
    ignore_groups: state.groupsIgnore,
    sign_msg: state.signMsg,
    convert_markdown_outbound: state.convertMarkdownOutbound,
    convert_markdown_inbound: state.convertMarkdownInbound,
    send_random_delay: state.sendRandomDelay,
    mark_read_on_reply: state.markReadOnReply,
    mark_read_on_open: state.markReadOnOpen,
    notify_send_errors_private: state.notifySendErrorsPrivate,
    send_templates_as_text: state.sendTemplatesAsText,
    ignore_from_me_echo: state.ignoreFromMeEcho,
    reject_call: state.rejectCall,
    read_messages: state.readMessages,
    always_online: state.alwaysOnline,
    ignore_status: state.ignoreStatus,
    msg_call: state.msgCall,
    merge_brazil_contacts: state.mergeBrazilContacts,
    import_contacts: state.importContacts,
    import_messages: state.importMessages,
    days_limit_import_messages: Math.min(
      Math.max(Number(state.daysLimitImportMessages) || 100, 1),
      1000
    ),
    import_on_connect: state.importOnConnect,
    mark_inbound_deleted: state.markInboundDeleted,
    mark_inbound_edited: state.markInboundEdited,
    sync_delete_to_whatsapp: state.syncDeleteToWhatsapp,
    sync_edit_to_whatsapp: state.syncEditToWhatsapp,
    proxy_enabled: state.proxyEnabled,
    proxy_host: state.proxyHost,
    proxy_port: state.proxyPort,
    proxy_username: state.proxyUsername,
  };

  if (state.proxyPassword) {
    config.proxy_password = state.proxyPassword;
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

  const updatedInbox = store.getters['inboxes/getInbox'](props.inbox.id);
  const syncError = updatedInbox?.provider_config?.settings_sync_error;
  if (syncError) {
    useAlert(
      t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_ERROR', { error: syncError })
    );
    return;
  }

  if (showSuccessAlert) {
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  }
}

async function saveSettings() {
  isSaving.value = true;
  try {
    await persistSettings();
  } catch {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isSaving.value = false;
  }
}

function requestImport() {
  if (isImporting.value) return;
  if (!state.importContacts && !state.importMessages) return;
  showImportConfirmModal.value = true;
}

async function runImport() {
  if (isImporting.value) return;

  isImporting.value = true;
  try {
    await persistSettings({ showSuccessAlert: false });
    const payload = await store.dispatch(
      'inboxes/evolutionGoImport',
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

async function confirmImport() {
  showImportConfirmModal.value = false;
  await runImport();
}

async function refreshContactProfiles() {
  if (isRefreshingContacts.value) return;

  isRefreshingContacts.value = true;
  try {
    const payload = await store.dispatch(
      'inboxes/evolutionGoRefreshContacts',
      props.inbox.id
    );
    useAlert(
      t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.REFRESH_CONTACTS.RUN_SUCCESS', {
        count: payload.enqueued || 0,
        minutes: Math.max(
          1,
          Math.ceil((payload.eta_seconds || 0) / 60) ||
            Math.ceil((payload.enqueued || 0) / 20)
        ),
      })
    );
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.REFRESH_CONTACTS.RUN_ERROR')
    );
  } finally {
    isRefreshingContacts.value = false;
  }
}

function importStatusLabel(status) {
  if (!status) return '';
  const key = status.toUpperCase();
  return t(`INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.STATUS.${key}`, status);
}

async function removeProxy() {
  isRemovingProxy.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        provider_config: {
          ...buildProviderConfig(),
          proxy_enabled: false,
          proxy_host: '',
          proxy_port: '',
          proxy_username: '',
          proxy_password: '',
        },
      },
    });
    state.proxyEnabled = false;
    state.proxyHost = '';
    state.proxyPort = '';
    state.proxyUsername = '';
    state.proxyPassword = '';
    useAlert(t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.PROXY.REMOVED'));
  } catch {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isRemovingProxy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-6">
    <EvolutionGoHealthPage :inbox="inbox" />

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
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.API_SYNC_NOTE') }}
      </p>
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
        <TextArea v-model="state.msgCall" rows="2" />
      </SettingsFieldSection>
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
        v-model="state.markReadOnReply"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.MARK_READ_ON_REPLY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.MARK_READ_ON_REPLY.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.markReadOnOpen"
        :header="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_READ_ON_OPEN.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_READ_ON_OPEN.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.sendRandomDelay"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_RANDOM_DELAY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_RANDOM_DELAY.DESCRIPTION')
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
        v-model="state.sendTemplatesAsText"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_TEMPLATES_AS_TEXT.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_TEMPLATES_AS_TEXT.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.FILTERS_SECTION')"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.INBOUND_ONLY_NOTE') }}
      </p>
      <SettingsToggleSection
        v-model="state.ignoreStatus"
        :header="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_STATUS_BROADCAST.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_STATUS_BROADCAST.DESCRIPTION')
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
        v-model="state.markInboundDeleted"
        :header="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_INBOUND_DELETED.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_INBOUND_DELETED.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.markInboundEdited"
        :header="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_INBOUND_EDITED.LABEL')
        "
        :description="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_INBOUND_EDITED.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IRREVERSIBLE_SECTION')"
    >
      <p class="text-sm text-n-amber-11">
        {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.SYNC_DELETE_WARNING') }}
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
        v-model="state.syncEditToWhatsapp"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_EDIT_TO_WHATSAPP.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_EDIT_TO_WHATSAPP.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT_SECTION')"
    >
      <SettingsToggleSection
        v-model="state.importOnConnect"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.ON_CONNECT.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.ON_CONNECT.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.importContacts"
        :header="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.CONTACTS.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.CONTACTS.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.importMessages"
        :header="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.MESSAGES.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.MESSAGES.DESCRIPTION')
        "
      />
      <p
        v-if="state.importMessages && !state.importContacts"
        class="text-sm text-n-amber-11"
      >
        {{
          t(
            'INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.MESSAGES_REQUIRES_CONTACTS'
          )
        }}
      </p>
      <SettingsFieldSection
        v-if="state.importMessages"
        :label="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.HISTORY_COUNT.LABEL')"
        :help-text="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT.HISTORY_COUNT.DESCRIPTION')
        "
      >
        <Input
          v-model="state.daysLimitImportMessages"
          type="number"
          min="1"
          max="1000"
        />
      </SettingsFieldSection>
      <SettingsToggleSection
        v-model="state.mergeBrazilContacts"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.MERGE_BRAZIL_CONTACTS.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.MERGE_BRAZIL_CONTACTS.DESCRIPTION')
        "
      />
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
          {{ t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.ERROR_LABEL') }}:
          {{ importStatus.error }}
        </p>
      </div>
      <div class="flex justify-end gap-2 flex-wrap">
        <NextButton
          :label="
            t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.REFRESH_CONTACTS.RUN')
          "
          :is-loading="isRefreshingContacts"
          slate
          @click="refreshContactProfiles"
        />
        <NextButton
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.RUN')"
          :is-loading="isImporting"
          :disabled="!state.importContacts && !state.importMessages"
          @click="requestImport"
        />
      </div>
      <p class="text-sm text-n-slate-11">
        {{
          t(
            'INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.REFRESH_CONTACTS.DESCRIPTION'
          )
        }}
      </p>
    </SettingsAccordion>

    <SettingsAccordion
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY_SECTION')"
    >
      <p v-if="hasExistingProxy" class="text-sm text-n-amber-11">
        {{ t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.PROXY_CREATE_ONLY') }}
      </p>
      <SettingsToggleSection
        v-model="state.proxyEnabled"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.ENABLED.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.ENABLED.DESCRIPTION')
        "
        :disabled="proxyEditDisabled"
      />
      <template v-if="state.proxyEnabled">
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.HOST.LABEL')"
        >
          <Input v-model="state.proxyHost" :disabled="proxyEditDisabled" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PORT.LABEL')"
        >
          <Input
            v-model="state.proxyPort"
            type="number"
            :disabled="proxyEditDisabled"
          />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.USERNAME.LABEL')"
        >
          <Input v-model="state.proxyUsername" :disabled="proxyEditDisabled" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PASSWORD.LABEL')"
        >
          <Input
            v-model="state.proxyPassword"
            :disabled="proxyEditDisabled"
            type="password"
            :placeholder="MASKED_SECRET"
          />
        </SettingsFieldSection>
      </template>
      <NextButton
        v-if="hasExistingProxy"
        variant="faded"
        color="ruby"
        :is-loading="isRemovingProxy"
        :label="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.PROXY.REMOVE')"
        @click="removeProxy"
      />
    </SettingsAccordion>

    <div class="flex justify-end">
      <NextButton
        :label="t('INBOX_MGMT.SETTINGS_POPUP.UPDATE')"
        :is-loading="isSaving"
        @click="saveSettings"
      />
    </div>

    <woot-delete-modal
      v-model:show="showImportConfirmModal"
      :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.IMPORT.RUN')"
      :message="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT_RUN_WARNING')"
      :confirm-text="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.IMPORT_RUN_CONFIRM')"
      :reject-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.CANCEL')"
      :on-confirm="confirmImport"
      :on-close="() => (showImportConfirmModal = false)"
    />
  </div>
</template>
