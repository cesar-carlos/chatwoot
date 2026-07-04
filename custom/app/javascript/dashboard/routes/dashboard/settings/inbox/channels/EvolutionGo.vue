<script setup>
import { reactive, computed, ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required, url, helpers } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import InboxesAPI from 'dashboard/api/inboxes';

import PageHeader from 'dashboard/routes/dashboard/settings/SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import EvolutionGoQrScanModal from 'customDashboard/components/evolution_go/EvolutionGoQrScanModal.vue';
import evolutionLogo from 'customDashboard/assets/images/channels/evolution-logo.png';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const state = reactive({
  inboxName: '',
  baseUrl: '',
  globalApiKey: '',
  instanceName: '',
  instanceToken: '',
  useExistingInstance: false,
  proxyEnabled: false,
  proxyHost: '',
  proxyPort: '',
  proxyUsername: '',
  proxyPassword: '',
});

const step = ref('form');
const inboxId = ref(null);
const isQrModalOpen = ref(false);
const qrModalRef = ref(null);
const isSubmitting = ref(false);

const uiFlags = useMapGetter('inboxes/getUIFlags');

const INSTANCE_NAME_PATTERN = /^[a-zA-Z0-9_-]+$/;

const validationRules = computed(() => ({
  inboxName: { required },
  baseUrl: { required, url },
  globalApiKey: state.useExistingInstance ? {} : { required },
  instanceName: {
    required,
    validFormat: helpers.withMessage(
      t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_NAME.FORMAT_ERROR'),
      value => INSTANCE_NAME_PATTERN.test((value || '').trim())
    ),
  },
  instanceToken: state.useExistingInstance ? { required } : {},
}));

const v$ = useVuelidate(validationRules, state);
const isSubmitDisabled = computed(() => v$.value.$invalid);

const formErrors = computed(() => ({
  inboxName: v$.value.inboxName?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION_GO.INBOX_NAME.ERROR')
    : '',
  baseUrl: v$.value.baseUrl?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION_GO.BASE_URL.ERROR')
    : '',
  globalApiKey: v$.value.globalApiKey?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION_GO.GLOBAL_API_KEY.ERROR')
    : '',
  instanceName: v$.value.instanceName?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_NAME.ERROR')
    : '',
  instanceToken: v$.value.instanceToken?.$error
    ? t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_TOKEN.ERROR')
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
    const normalizedBaseUrl = state.baseUrl.trim().replace(/\/$/, '');
    try {
      await InboxesAPI.postEvolutionGoServerCheck({
        base_url: normalizedBaseUrl,
        global_api_key: state.useExistingInstance
          ? undefined
          : state.globalApiKey.trim(),
      });
    } catch (error) {
      useAlert(
        error?.response?.data?.error ||
          t('INBOX_MGMT.ADD.EVOLUTION_GO.SERVER_CHECK.ERROR')
      );
      return;
    }

    const channelPayload = {
      type: 'whatsapp',
      provider: 'evolution_go',
        base_url: normalizedBaseUrl,
      instance_name: state.instanceName.trim(),
      provider_config: {
        proxy_enabled: state.proxyEnabled,
        proxy_host: state.proxyHost,
        proxy_port: state.proxyPort,
        proxy_username: state.proxyUsername,
        proxy_password: state.proxyPassword,
      },
    };

    if (state.useExistingInstance) {
      channelPayload.instance_token = state.instanceToken.trim();
    } else {
      channelPayload.global_api_key = state.globalApiKey.trim();
    }

    const inbox = await store.dispatch('inboxes/createEvolutionGoChannel', {
      name: state.inboxName.trim(),
      channel: channelPayload,
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
        t('INBOX_MGMT.ADD.EVOLUTION_GO.API.ERROR_MESSAGE')
    );
  } finally {
    isSubmitting.value = false;
  }
}
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.EVOLUTION_GO.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.EVOLUTION_GO.DESC')"
    />

    <div v-if="step === 'form'" class="max-w-xl space-y-4">
      <Input
        v-model="state.inboxName"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.INBOX_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_GO.INBOX_NAME.PLACEHOLDER')"
        :message="formErrors.inboxName"
        :message-type="formErrors.inboxName ? 'error' : 'info'"
      />
      <Input
        v-model="state.baseUrl"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.BASE_URL.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_GO.BASE_URL.PLACEHOLDER')"
        :message="formErrors.baseUrl"
        :message-type="formErrors.baseUrl ? 'error' : 'info'"
      />

      <div class="flex items-center justify-between gap-4 pt-2">
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_MGMT.ADD.EVOLUTION_GO.EXISTING_INSTANCE.LABEL') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('INBOX_MGMT.ADD.EVOLUTION_GO.EXISTING_INSTANCE.DESCRIPTION') }}
          </p>
        </div>
        <ToggleSwitch v-model="state.useExistingInstance" />
      </div>

      <Input
        v-if="!state.useExistingInstance"
        v-model="state.globalApiKey"
        type="password"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.GLOBAL_API_KEY.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_GO.GLOBAL_API_KEY.PLACEHOLDER')"
        :message="
          formErrors.globalApiKey ||
          t('INBOX_MGMT.ADD.EVOLUTION_GO.GLOBAL_API_KEY.HELP')
        "
        :message-type="formErrors.globalApiKey ? 'error' : 'info'"
      />
      <Input
        v-else
        v-model="state.instanceToken"
        type="password"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_TOKEN.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_TOKEN.PLACEHOLDER')"
        :message="formErrors.instanceToken"
        :message-type="formErrors.instanceToken ? 'error' : 'info'"
      />

      <Input
        v-model="state.instanceName"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.EVOLUTION_GO.INSTANCE_NAME.PLACEHOLDER')"
        :message="formErrors.instanceName"
        :message-type="formErrors.instanceName ? 'error' : 'info'"
      />

      <div class="pt-4 mt-2 border-t border-n-weak space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div>
            <p class="text-sm font-medium text-n-slate-12">
              {{ t('INBOX_MGMT.ADD.EVOLUTION_GO.PROXY.ENABLED.LABEL') }}
            </p>
          </div>
          <ToggleSwitch v-model="state.proxyEnabled" />
        </div>
        <div v-if="state.proxyEnabled" class="grid grid-cols-2 gap-3">
          <Input
            v-model="state.proxyHost"
            :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.PROXY.HOST')"
            class="col-span-2"
          />
          <Input
            v-model="state.proxyPort"
            :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.PROXY.PORT')"
          />
          <Input
            v-model="state.proxyUsername"
            :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.PROXY.USERNAME')"
          />
          <Input
            v-model="state.proxyPassword"
            :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.PROXY.PASSWORD')"
            type="password"
          />
        </div>
      </div>

      <NextButton
        type="button"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.SUBMIT_BUTTON')"
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
        :alt="t('INBOX_MGMT.ADD.EVOLUTION_GO.LOGO_ALT')"
        class="size-16"
      />
      <div>
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('INBOX_MGMT.ADD.EVOLUTION_GO.CONNECT.TITLE') }}
        </h2>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ t('INBOX_MGMT.ADD.EVOLUTION_GO.CONNECT.DESCRIPTION') }}
        </p>
      </div>
      <NextButton
        type="button"
        :label="t('INBOX_MGMT.ADD.EVOLUTION_GO.CONNECT.OPEN_QR')"
        @click="openQrReader"
      />
    </div>

    <EvolutionGoQrScanModal
      v-if="inboxId"
      ref="qrModalRef"
      v-model="isQrModalOpen"
      :inbox-id="inboxId"
      fetch-fresh-qr
      @connected="onWizardConnected"
    />
  </div>
</template>
