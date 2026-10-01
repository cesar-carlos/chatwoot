<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
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
import { BROWSER_PUSH_SYNC_EVENT } from 'customDashboard/helper/pushResume';
import {
  isPushSessionActive,
  isCurrentPushSession,
  pushSession,
} from 'customDashboard/helper/pushSession';
import { testBrowserSubscription } from 'customDashboard/api/notificationSubscription';

const emit = defineEmits(['permissionChange']);

const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const {
  status: installStatus,
  promptInstall,
  checkInstallability,
} = usePwaInstallation();

const initialPushEnvironment = getPushEnvironment();
const pushStatus = ref(
  initialPushEnvironment.supported &&
    initialPushEnvironment.permission === 'granted'
    ? 'checking'
    : initialPushEnvironment.status
);
const pushEnabled = ref(false);
const pushUpdating = ref(false);
const subscriptionEndpoint = ref(null);
const testing = ref(false);
let mounted = true;
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
    checking: 'PUSH_STATUS_CHECKING',
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
    testing.value ||
    pushUpdating.value ||
    ['unsupported', 'requires_install', 'denied', 'checking'].includes(
      pushStatus.value
    )
);

const reportPartialCleanup = result => {
  if (result.cleanupError) {
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_STALE_CLEANUP_ERROR'));
  }
  if (result.serverError) {
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_UNSUBSCRIBE_ERROR'));
  }
};

const handlePushSync = event => {
  if (pushUpdating.value || !isPushSessionActive()) return;
  const { status, permission, cleanupError } = event.detail;
  pushStatus.value = status;
  pushEnabled.value = status === 'subscribed';
  subscriptionEndpoint.value = event.detail.endpoint || null;
  emit('permissionChange', permission);
  if (cleanupError) {
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_STALE_CLEANUP_ERROR'));
  }
};

const refreshPushSubscription = async () => {
  if (!isPushSessionActive()) return;
  const session = pushSession();
  const environment = getPushEnvironment();
  pushStatus.value =
    environment.supported && environment.permission === 'granted'
      ? 'checking'
      : environment.status;
  emit('permissionChange', environment.permission);

  if (!environment.supported || environment.permission !== 'granted') return;

  try {
    const result = await ensurePushSubscription();
    if (!mounted || !isCurrentPushSession(session)) return;
    pushStatus.value = result.status;
    pushEnabled.value = result.status === 'subscribed';
    subscriptionEndpoint.value = result.subscription?.endpoint || null;
    reportPartialCleanup(result);
  } catch (error) {
    if (!mounted || !isCurrentPushSession(session)) return;
    pushStatus.value = 'error';
  }
};

const updatePushSubscription = async () => {
  if (pushUpdating.value || !isPushSessionActive()) return;
  const session = pushSession();
  const previousValue = !pushEnabled.value;
  pushUpdating.value = true;

  try {
    const result = pushEnabled.value
      ? await requestAndSubscribe()
      : await unsubscribePush();
    if (!mounted || !isCurrentPushSession(session)) return;
    pushStatus.value = result.status;
    pushEnabled.value = result.status === 'subscribed';
    subscriptionEndpoint.value = result.subscription?.endpoint || null;
    emit('permissionChange', result.permission);
    reportPartialCleanup(result);
  } catch (error) {
    if (!mounted || !isCurrentPushSession(session)) return;
    pushStatus.value = 'error';
    pushEnabled.value = previousValue;
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_SUBSCRIPTION_ERROR'));
  } finally {
    if (mounted && isCurrentPushSession(session)) pushUpdating.value = false;
  }
};

const testPush = async () => {
  if (testing.value || !subscriptionEndpoint.value || !isPushSessionActive())
    return;
  const session = pushSession();
  testing.value = true;
  try {
    await testBrowserSubscription(subscriptionEndpoint.value);
    if (mounted && isCurrentPushSession(session))
      useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_TEST_ACCEPTED'));
  } catch (error) {
    if (mounted && isCurrentPushSession(session))
      useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_TEST_ERROR'));
  } finally {
    if (mounted && isCurrentPushSession(session)) testing.value = false;
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

onMounted(() => {
  window.addEventListener(BROWSER_PUSH_SYNC_EVENT, handlePushSync);
  checkInstallability();
  refreshPushSubscription();
});
onUnmounted(() => {
  mounted = false;
  window.removeEventListener(BROWSER_PUSH_SYNC_EVENT, handlePushSync);
});
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
    <Button
      v-if="pushStatus === 'subscribed' && subscriptionEndpoint"
      sm
      faded
      :label="t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.PUSH_TEST_ACTION')"
      :disabled="testing || pushUpdating"
      :is-loading="testing"
      @click="testPush"
    />
  </div>
</template>
