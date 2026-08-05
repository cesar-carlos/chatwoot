<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164 } from 'shared/helpers/Validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import PageHeader from 'dashboard/routes/dashboard/settings/SettingsSubPageHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const state = reactive({
  inboxName: '',
  phoneNumber: '',
  deviceToken: '',
  inboundCallsEnabled: true,
});

const uiFlags = useMapGetter('inboxes/getUIFlags');

const validationRules = {
  inboxName: { required },
  phoneNumber: { required, isPhoneE164 },
  deviceToken: { required },
};

const v$ = useVuelidate(validationRules, state);
const isSubmitDisabled = computed(() => v$.value.$invalid);

const formErrors = computed(() => ({
  inboxName: v$.value.inboxName?.$error
    ? t('INBOX_MGMT.ADD.WAVOIP.INBOX_NAME.ERROR')
    : '',
  phoneNumber: v$.value.phoneNumber?.$error
    ? t('INBOX_MGMT.ADD.WAVOIP.PHONE_NUMBER.ERROR')
    : '',
  deviceToken: v$.value.deviceToken?.$error
    ? t('INBOX_MGMT.ADD.WAVOIP.DEVICE_TOKEN.ERROR')
    : '',
}));

async function createChannel() {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  try {
    const channel = await store.dispatch('inboxes/createWavoipChannel', {
      name: state.inboxName,
      wavoip: {
        phone_number: state.phoneNumber,
        device_token: state.deviceToken,
        provider_config: {
          inbound_calls_enabled: state.inboundCallsEnabled,
        },
      },
    });

    const webhookUrl = channel.wavoip_webhook_url || channel.wavoipWebhookUrl;
    if (webhookUrl) {
      useAlert(t('INBOX_MGMT.ADD.WAVOIP.WEBHOOK_HINT', { url: webhookUrl }));
    }

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: channel.id },
    });
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        t('INBOX_MGMT.ADD.WAVOIP.API.ERROR_MESSAGE')
    );
  }
}
</script>

<template>
  <div class="overflow-auto col-span-6 p-6 w-full h-full">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.WAVOIP.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.WAVOIP.DESC')"
    />

    <form
      class="flex flex-col gap-4 flex-wrap mx-0"
      @submit.prevent="createChannel"
    >
      <Input
        v-model="state.inboxName"
        :label="t('INBOX_MGMT.ADD.WAVOIP.INBOX_NAME.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.WAVOIP.INBOX_NAME.PLACEHOLDER')"
        :message="formErrors.inboxName"
        :message-type="formErrors.inboxName ? 'error' : 'info'"
        @blur="v$.inboxName?.$touch"
      />

      <Input
        v-model="state.phoneNumber"
        :label="t('INBOX_MGMT.ADD.WAVOIP.PHONE_NUMBER.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.WAVOIP.PHONE_NUMBER.PLACEHOLDER')"
        :message="
          formErrors.phoneNumber ||
          t('INBOX_MGMT.ADD.WAVOIP.PHONE_NUMBER.HELP_TEXT')
        "
        :message-type="formErrors.phoneNumber ? 'error' : 'info'"
        @blur="v$.phoneNumber?.$touch"
      />

      <Input
        v-model="state.deviceToken"
        type="password"
        :label="t('INBOX_MGMT.ADD.WAVOIP.DEVICE_TOKEN.LABEL')"
        :placeholder="t('INBOX_MGMT.ADD.WAVOIP.DEVICE_TOKEN.PLACEHOLDER')"
        :message="formErrors.deviceToken"
        :message-type="formErrors.deviceToken ? 'error' : 'info'"
        @blur="v$.deviceToken?.$touch"
      />

      <div class="flex items-center justify-between gap-2">
        <div>
          <p class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_MGMT.ADD.WAVOIP.INBOUND.LABEL') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('INBOX_MGMT.ADD.WAVOIP.INBOUND.DESCRIPTION') }}
          </p>
        </div>
        <ToggleSwitch v-model="state.inboundCallsEnabled" />
      </div>

      <p class="text-xs text-n-slate-11">
        {{ t('INBOX_MGMT.ADD.WAVOIP.SETUP_NOTE') }}
      </p>

      <div>
        <NextButton
          :is-loading="uiFlags.isCreating"
          :disabled="isSubmitDisabled"
          :label="t('INBOX_MGMT.ADD.WAVOIP.SUBMIT_BUTTON')"
          type="submit"
        />
      </div>
    </form>
  </div>
</template>
