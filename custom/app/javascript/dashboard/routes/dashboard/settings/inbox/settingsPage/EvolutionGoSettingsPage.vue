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
import EvolutionGoHealthPage from 'customDashboard/routes/dashboard/settings/inbox/settingsPage/EvolutionGoHealthPage.vue';

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

function loadState() {
  const config = props.inbox.provider_config || {};

  return {
    groupsIgnore: config.ignore_groups !== false,
    signMsg: config.sign_msg === true,
    convertMarkdownOutbound: config.convert_markdown_outbound !== false,
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

watch(
  () => props.inbox.id,
  () => {
    Object.assign(state, loadState());
  },
  { immediate: true }
);

function buildProviderConfig() {
  const existing = { ...(props.inbox.provider_config || {}) };

  const config = {
    ...existing,
    ignore_groups: state.groupsIgnore,
    sign_msg: state.signMsg,
    convert_markdown_outbound: state.convertMarkdownOutbound,
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

async function saveSettings() {
  isSaving.value = true;
  try {
    const updatedInbox = await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      inbox: {
        provider_config: buildProviderConfig(),
      },
    });

    const syncError = updatedInbox?.provider_config?.settings_sync_error;
    if (syncError) {
      useAlert(
        t('INBOX_MGMT.EVOLUTION.SETTINGS.SYNC_ERROR', { error: syncError })
      );
    } else {
      useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    }
  } catch {
    useAlert(t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
  } finally {
    isSaving.value = false;
  }
}

async function removeProxy() {
  isRemovingProxy.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      inbox: {
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

    <p v-if="settingsSyncError" class="text-sm text-n-ruby-11">
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
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.GROUPS_IGNORE.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.GROUPS_IGNORE.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.rejectCall"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.REJECT_CALL.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.REJECT_CALL.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.readMessages"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.READ_MESSAGES.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.READ_MESSAGES.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.alwaysOnline"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.ALWAYS_ONLINE.LABEL')"
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
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_MSG.LABEL')"
        :description="t('INBOX_MGMT.EVOLUTION.SETTINGS.SIGN_MSG.DESCRIPTION')"
      />
      <SettingsToggleSection
        v-model="state.convertMarkdownOutbound"
        :label="
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
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.MARK_READ_ON_REPLY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.MARK_READ_ON_REPLY.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.markReadOnOpen"
        :label="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_READ_ON_OPEN.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.MARK_READ_ON_OPEN.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.sendRandomDelay"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_RANDOM_DELAY.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.SEND_RANDOM_DELAY.DESCRIPTION')
        "
      />
      <SettingsToggleSection
        v-model="state.notifySendErrorsPrivate"
        :label="
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
        :label="
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
      <SettingsToggleSection
        v-model="state.ignoreFromMeEcho"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_FROM_ME_ECHO.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.IGNORE_FROM_ME_ECHO.DESCRIPTION')
        "
      />
    </SettingsAccordion>

    <SettingsAccordion :title="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY_SECTION')">
      <SettingsToggleSection
        v-model="state.proxyEnabled"
        :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.ENABLED.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.ENABLED.DESCRIPTION')
        "
      />
      <template v-if="state.proxyEnabled">
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.HOST.LABEL')"
        >
          <Input v-model="state.proxyHost" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PORT.LABEL')"
        >
          <Input v-model="state.proxyPort" type="number" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.USERNAME.LABEL')"
        >
          <Input v-model="state.proxyUsername" />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_MGMT.EVOLUTION.SETTINGS.PROXY.PASSWORD.LABEL')"
        >
          <Input
            v-model="state.proxyPassword"
            type="password"
            :placeholder="MASKED_SECRET"
          />
        </SettingsFieldSection>
      </template>
      <NextButton
        v-if="inbox.provider_config?.proxy_host"
        variant="faded"
        color="ruby"
        :is-loading="isRemovingProxy"
        :label="t('INBOX_MGMT.EVOLUTION_GO.SETTINGS.PROXY.REMOVE')"
        @click="removeProxy"
      />
    </SettingsAccordion>

    <div class="flex justify-end">
      <NextButton
        :label="t('INBOX_MGMT.SETTINGS.SAVE')"
        :is-loading="isSaving"
        @click="saveSettings"
      />
    </div>
  </div>
</template>
