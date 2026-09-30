<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useBranding } from 'shared/composables/useBranding';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import {
  ensurePushSubscription,
  getPushEnvironment,
  requestAndSubscribe,
  unsubscribePush,
} from 'customDashboard/helper/pushHelper';
import { usePwaInstallation } from 'customDashboard/composables/usePwaInstallation';

const emit = defineEmits(['permissionChange']);

const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const { status: installStatus, promptInstall } = usePwaInstallation();

const pushStatus = ref(getPushEnvironment().status);
const pushEnabled = ref(false);
const pushUpdating = ref(false);
const installUpdating = ref(false);

const brandedText = key => replaceInstallationName(t(key));

const pushStatusMessage = computed(() => {
  const statusKeys = {
    unsupported: 'PUSH_STATUS_UNSUPPORTED',
    requires_install: 'PUSH_STATUS_REQUIRES_INSTALL',
    default: 'PUSH_STATUS_DEFAULT',
    denied: 'PUSH_STATUS_DENIED',
    subscribed: 'PUSH_STATUS_SUBSCRIBED',
    unsubscribed: 'PUSH_STATUS_UNSUBSCRIBED',
    error: 'PUSH_STATUS_ERROR',
  };
  const key = statusKeys[pushStatus.value] || statusKeys.error;
  return brandedText(`PROFILE_SETTINGS.FORM.NOTIFICATIONS.${key}`);
});

const installStatusMessage = computed(() =>
  brandedText(
    `PROFILE_SETTINGS.FORM.NOTIFICATIONS.PWA_INSTALL_STATUS_${installStatus.value.toUpperCase()}`
  )
);

const pushToggleDisabled = computed(
  () =>
    pushUpdating.value ||
    ['unsupported', 'requires_install', 'denied'].includes(pushStatus.value)
);

const reportPartialCleanup = result => {
  if (result.cleanupError) {
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_STALE_CLEANUP_ERROR'));
  }
  if (result.serverError) {
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_UNSUBSCRIBE_ERROR'));
  }
};

const refreshPushSubscription = async () => {
  const environment = getPushEnvironment();
  pushStatus.value = environment.status;
  pushEnabled.value = false;
  emit('permissionChange', environment.permission);

  if (!environment.supported || environment.permission !== 'granted') return;

  try {
    const result = await ensurePushSubscription();
    pushStatus.value = result.status;
    pushEnabled.value = result.status === 'subscribed';
    reportPartialCleanup(result);
  } catch (error) {
    pushStatus.value = 'error';
  }
};

const updatePushSubscription = async () => {
  const previousValue = !pushEnabled.value;
  pushUpdating.value = true;

  try {
    const result = pushEnabled.value
      ? await requestAndSubscribe()
      : await unsubscribePush();
    pushStatus.value = result.status;
    pushEnabled.value = result.status === 'subscribed';
    emit('permissionChange', result.permission);
    reportPartialCleanup(result);
  } catch (error) {
    pushStatus.value = 'error';
    pushEnabled.value = previousValue;
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_SUBSCRIPTION_ERROR'));
  } finally {
    pushUpdating.value = false;
  }
};

const install = async () => {
  installUpdating.value = true;
  try {
    const choice = await promptInstall();
    if (choice.outcome === 'dismissed') {
      useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PWA_INSTALL_DISMISSED'));
    }
  } catch (error) {
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PWA_INSTALL_ERROR'));
  } finally {
    installUpdating.value = false;
  }
};

onMounted(refreshPushSubscription);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      class="flex flex-col items-start justify-between gap-3 rounded-xl border border-n-weak p-4 sm:flex-row sm:items-center"
    >
      <div class="flex flex-col gap-1">
        <span class="text-body-main text-n-slate-12">
          {{ t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PWA_INSTALL_TITLE') }}
        </span>
        <span class="text-body-small text-n-slate-11">
          {{ installStatusMessage }}
        </span>
      </div>
      <Button
        v-if="installStatus === 'available'"
        sm
        :label="t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PWA_INSTALL_ACTION')"
        :is-loading="installUpdating"
        :disabled="installUpdating"
        @click="install"
      />
    </div>

    <div
      class="flex items-center justify-between w-full gap-2 p-4 border border-solid border-n-weak rounded-xl"
    >
      <div class="flex flex-row items-center gap-2">
        <fluent-icon
          icon="alert"
          class="flex-shrink-0 text-n-slate-12"
          size="18"
        />
        <div class="flex flex-col gap-1">
          <span class="text-body-main text-n-slate-12">
            {{ t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.BROWSER_PERMISSION') }}
          </span>
          <span class="text-body-small text-n-slate-11">
            {{ pushStatusMessage }}
          </span>
        </div>
      </div>
      <ToggleSwitch
        v-model="pushEnabled"
        :disabled="pushToggleDisabled"
        @change="updatePushSubscription"
      />
    </div>
  </div>
</template>
