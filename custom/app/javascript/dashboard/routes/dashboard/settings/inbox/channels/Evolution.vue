<script setup>
import { reactive, computed, ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PageHeader from 'dashboard/routes/dashboard/settings/SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import EvolutionQrScanModal from 'customDashboard/components/evolution/EvolutionQrScanModal.vue';
import evolutionLogo from 'customDashboard/assets/images/channels/evolution-logo.png';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

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
const isQrModalOpen = ref(false);
const qrModalRef = ref(null);
const isSubmitting = ref(false);

const uiFlags = useMapGetter('inboxes/getUIFlags');

const validationRules = {
  inboxName: { required },
  baseUrl: { required, url },
  apiKey: { required },
  instanceName: { required },
};

const v$ = useVuelidate(validationRules, state);
const isSubmitDisabled = computed(() => v$.value.$invalid);

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

function onWizardConnected() {
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: inboxId.value },
  });
}

async function openQrReader() {
  if (isQrModalOpen.value) {
    qrModalRef.value?.open();
    return;
  }

  isQrModalOpen.value = true;
  await nextTick();
  qrModalRef.value?.open();
}

async function createChannel() {
  if (isSubmitting.value || uiFlags.value.isCreating || step.value !== 'form') {
    return;
  }

  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  isSubmitting.value = true;
  try {
    const inbox = await store.dispatch('inboxes/createEvolutionChannel', {
      name: state.inboxName.trim(),
      channel: {
        type: 'whatsapp',
        provider: 'evolution',
        base_url: state.baseUrl.trim().replace(/\/$/, ''),
        api_key: state.apiKey.trim(),
        instance_name: state.instanceName.trim(),
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

    inboxId.value = inbox.id;
    step.value = 'connect';
    isQrModalOpen.value = true;
  } catch (error) {
    inboxId.value = null;
    step.value = 'form';
    isQrModalOpen.value = false;
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.ADD.EVOLUTION.API.ERROR_MESSAGE')
    );
  } finally {
    isSubmitting.value = false;
  }
}
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
        type="password"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.API_KEY.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION.API_KEY.PLACEHOLDER')"
        :message="
          formErrors.apiKey || t('INBOX_MGMT.ADD.EVOLUTION.API_KEY.HELP')
        "
        :message-type="formErrors.apiKey ? 'error' : 'info'"
      />
      <Input
        v-model="state.instanceName"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.PLACEHOLDER')"
        :message="formErrors.instanceName"
        :message-type="formErrors.instanceName ? 'error' : 'info'"
      />

      <div class="pt-4 mt-2 border-t border-n-weak space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('INBOX_MGMT.ADD.EVOLUTION.PROXY.ENABLED.LABEL') }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('INBOX_MGMT.ADD.EVOLUTION.PROXY.ENABLED.DESCRIPTION') }}
            </p>
          </div>
          <ToggleSwitch v-model="state.proxyEnabled" />
        </div>
        <div v-if="state.proxyEnabled" class="grid grid-cols-2 gap-3">
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
        type="button"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.SUBMIT_BUTTON')"
        :disabled="isSubmitDisabled || uiFlags.isCreating || isSubmitting"
        :is-loading="uiFlags.isCreating || isSubmitting"
        @click="createChannel"
      />
    </div>

    <div
      v-else
      class="flex flex-col items-center max-w-md mx-auto text-center gap-6"
    >
      <img
        :src="evolutionLogo"
        :alt="t('INBOX_MGMT.ADD.EVOLUTION.LOGO_ALT')"
        class="size-16"
      />
      <div>
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.EVOLUTION.CONNECT.TITLE') }}
        </h2>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.EVOLUTION.CONNECT.DESCRIPTION') }}
        </p>
      </div>
      <NextButton
        type="button"
        :label="t('INBOX_MGMT.ADD.EVOLUTION.CONNECT.OPEN_QR')"
        @click="openQrReader"
      />
    </div>

    <EvolutionQrScanModal
      v-if="inboxId"
      ref="qrModalRef"
      v-model="isQrModalOpen"
      :inbox-id="inboxId"
      fetch-fresh-qr
      @connected="onWizardConnected"
    />
  </div>
</template>
