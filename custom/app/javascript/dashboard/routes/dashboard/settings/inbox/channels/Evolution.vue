<script setup>
import { reactive, computed, ref, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useEvolutionConnectionCable } from 'customDashboard/composables/evolution/useEvolutionConnectionCable';

import PageHeader from 'dashboard/routes/dashboard/settings/SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import evolutionLogo from 'customDashboard/assets/images/channels/evolution-logo.png';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const POLL_MS = 3000;

const state = reactive({
  inboxName: '',
  baseUrl: '',
  apiKey: '',
  instanceName: '',
  proxyEnabled: false,
  proxyHost: '',
  proxyPort: '',
  proxyProtocol: 'http',
  proxyUsername: '',
  proxyPassword: '',
});

const step = ref('form');
const inboxId = ref(null);
const qrcodeBase64 = ref('');
const connectionStatus = ref('connecting');
let pollTimer = null;

const uiFlags = useMapGetter('inboxes/getUIFlags');

const validationRules = {
  inboxName: { required },
  baseUrl: { required, url },
  apiKey: { required },
  instanceName: { required },
};

const v$ = useVuelidate(validationRules, state);
const isSubmitDisabled = computed(() => v$.value.$invalid);

const isConnected = computed(() => connectionStatus.value === 'open');

const formErrors = computed(() => ({
  inboxName: v$.value.inboxName?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION.INBOX_NAME.ERROR')
    : '',
  baseUrl: v$.value.baseUrl?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION.BASE_URL.ERROR')
    : '',
  apiKey: v$.value.apiKey?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION.API_KEY.ERROR')
    : '',
  instanceName: v$.value.instanceName?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.ERROR')
    : '',
}));

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function applyConnectionPayload(payload) {
  if (payload.connectionStatus) {
    connectionStatus.value = payload.connectionStatus;
  }
  if (payload.qrcodeBase64) {
    qrcodeBase64.value = payload.qrcodeBase64;
  }

  if (isConnected.value) {
    stopPolling();
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: inboxId.value },
    });
  }
}

async function pollConnection() {
  if (!inboxId.value) return;

  try {
    const payload = await store.dispatch(
      'inboxes/fetchEvolutionConnection',
      inboxId.value
    );
    applyConnectionPayload({
      connectionStatus:
        payload.connectionStatus || payload.connection_status || 'connecting',
      qrcodeBase64: payload.qrcodeBase64 || payload.qrcode_base64,
    });
  } catch {
    // keep polling
  }
}

function startPolling() {
  stopPolling();
  pollConnection();
  pollTimer = setInterval(pollConnection, POLL_MS);
}

async function createChannel() {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    const channel = await store.dispatch('inboxes/createEvolutionChannel', {
      name: state.inboxName,
      channel: {
        type: 'whatsapp',
        provider: 'evolution',
        base_url: state.baseUrl.replace(/\/$/, ''),
        api_key: state.apiKey,
        instance_name: state.instanceName,
        provider_config: {
          proxy_enabled: state.proxyEnabled,
          proxy_host: state.proxyHost,
          proxy_port: state.proxyPort,
          proxy_protocol: state.proxyProtocol,
          proxy_username: state.proxyUsername,
          proxy_password: state.proxyPassword,
        },
      },
    });

    inboxId.value = channel.id;
    step.value = 'qr';
    startPolling();
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.ADD.EVOLUTION.API.ERROR_MESSAGE')
    );
  }
}

useEvolutionConnectionCable(inboxId, applyConnectionPayload);

onUnmounted(stopPolling);
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.EVOLUTION.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.EVOLUTION.DESC')"
    />

    <div v-if="step === 'form'" class="max-w-xl space-y-4">
      <Input
        v-model="state.inboxName"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.INBOX_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION.INBOX_NAME.PLACEHOLDER')"
        :message="formErrors.inboxName"
        :message-type="formErrors.inboxName ? 'error' : 'info'"
      />
      <Input
        v-model="state.baseUrl"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.BASE_URL.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION.BASE_URL.PLACEHOLDER')"
        :message="formErrors.baseUrl"
        :message-type="formErrors.baseUrl ? 'error' : 'info'"
      />
      <Input
        v-model="state.apiKey"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.API_KEY.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION.API_KEY.PLACEHOLDER')"
        :message="formErrors.apiKey"
        :message-type="formErrors.apiKey ? 'error' : 'info'"
      />
      <Input
        v-model="state.instanceName"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.PLACEHOLDER')"
        :message="formErrors.instanceName"
        :message-type="formErrors.instanceName ? 'error' : 'info'"
      />

      <div class="pt-2 border-t border-n-weak">
        <ToggleSwitch
          v-model="state.proxyEnabled"
          :label="t('INBOX_MGMT.ADD.EVOLUTION.PROXY.ENABLED')"
        />
        <div v-if="state.proxyEnabled" class="grid grid-cols-2 gap-3 mt-4">
          <Input
            v-model="state.proxyHost"
            :label="t('INBOX_MGMT.ADD.EVOLUTION.PROXY.HOST')"
            class="col-span-2"
          />
          <Input
            v-model="state.proxyPort"
            :label="t('INBOX_MGMT.ADD.EVOLUTION.PROXY.PORT')"
          />
          <Input
            v-model="state.proxyProtocol"
            :label="t('INBOX_MGMT.ADD.EVOLUTION.PROXY.PROTOCOL')"
          />
          <Input
            v-model="state.proxyUsername"
            :label="t('INBOX_MGMT.ADD.EVOLUTION.PROXY.USERNAME')"
          />
          <Input
            v-model="state.proxyPassword"
            :label="t('INBOX_MGMT.ADD.EVOLUTION.PROXY.PASSWORD')"
            type="password"
          />
        </div>
      </div>

      <NextButton
        :label="t('INBOX_MGMT.ADD.EVOLUTION.SUBMIT_BUTTON')"
        :disabled="isSubmitDisabled || uiFlags.isCreating"
        :is-loading="uiFlags.isCreating"
        @click="createChannel"
      />
    </div>

    <div
      v-else
      class="flex flex-col items-center max-w-md mx-auto text-center gap-6"
    >
      <img :src="evolutionLogo" alt="Evolution API" class="size-16" />
      <div>
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.EVOLUTION.QR.TITLE') }}
        </h2>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.EVOLUTION.QR.DESCRIPTION') }}
        </p>
        <p class="mt-1 text-xs text-n-slate-10">
          {{
            t('INBOX_MGMT.ADD.EVOLUTION.QR.STATUS', {
              status: connectionStatus,
            })
          }}
        </p>
      </div>
      <div
        v-if="qrcodeBase64"
        class="p-4 rounded-2xl bg-white border border-n-weak"
      >
        <img
          :src="qrcodeBase64"
          alt="WhatsApp QR Code"
          class="w-64 h-64 object-contain"
        />
      </div>
      <p v-else class="text-sm text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.EVOLUTION.QR.LOADING') }}
      </p>
    </div>
  </div>
</template>
