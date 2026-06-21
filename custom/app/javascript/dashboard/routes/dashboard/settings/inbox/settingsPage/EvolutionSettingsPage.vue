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
    rejectCall: config.reject_call === true,
    readMessages: config.read_messages === true,
    reopenConversation: config.reopen_conversation !== false,
    conversationPending: config.conversation_pending === true,
    proxyEnabled: config.proxy_enabled === true,
    proxyHost: config.proxy_host || '',
    proxyPort: config.proxy_port || '',
    proxyProtocol: config.proxy_protocol || 'http',
    proxyUsername: config.proxy_username || '',
    proxyPassword: '',
    ignoreJidsText: (config.ignore_jids || ['@g.us']).join('\n'),
  };
}

const state = reactive(loadState());

watch(
  () => props.inbox.provider_config,
  () => {
    Object.assign(state, loadState());
  },
  { deep: true }
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
    reject_call: state.rejectCall,
    read_messages: state.readMessages,
    reopen_conversation: state.reopenConversation,
    conversation_pending: state.conversationPending,
    proxy_enabled: state.proxyEnabled,
    proxy_host: state.proxyHost,
    proxy_port: state.proxyPort,
    proxy_protocol: state.proxyProtocol,
    proxy_username: state.proxyUsername,
    ignore_jids: ignoreJids,
  };

  delete config.api_key;

  if (state.proxyPassword) {
    config.proxy_password = state.proxyPassword;
  } else if (config.proxy_password === MASKED_SECRET) {
    delete config.proxy_password;
  }

  return config;
}

async function saveSettings() {
  if (isSaving.value) return;

  isSaving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: {
        provider_config: buildProviderConfig(),
      },
    });
    useAlert(t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE')
    );
  } finally {
    isSaving.value = false;
  }
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
        v-model="state.reopenConversation"
        :header="t('INBOX_MGMT.EVOLUTION.SETTINGS.REOPEN_CONVERSATION.LABEL')"
        :description="
          t('INBOX_MGMT.EVOLUTION.SETTINGS.REOPEN_CONVERSATION.DESCRIPTION')
        "
      />
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
