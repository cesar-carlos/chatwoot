import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  ensurePushSubscription,
  getPushEnvironment,
  requestAndSubscribe,
  unsubscribePush,
} from 'customDashboard/helper/pushHelper';
import {
  BROWSER_PUSH_SYNC_EVENT,
  publishBrowserPushState,
} from 'customDashboard/helper/pushResume';
import {
  isCurrentPushSession,
  isPushSessionActive,
  pushSession,
} from 'customDashboard/helper/pushSession';
import { testBrowserSubscription } from 'customDashboard/api/notificationSubscription';

// One action lock for every surface; a click must not open a second prompt.
const busy = ref(false);
let activeOperation;
const translationPrefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';

export const usePushDevice = () => {
  const { t } = useI18n();
  const environment = getPushEnvironment();
  const permission = ref(environment.permission);
  const status = ref(
    environment.supported && permission.value === 'granted'
      ? 'checking'
      : environment.status
  );
  const endpoint = ref(null);
  let mounted = true;
  let refreshing;
  const subscribed = computed(() => status.value === 'subscribed');
  const disabled = computed(() => busy.value || status.value === 'checking');
  const alert = key => useAlert(t(`${translationPrefix}${key}`));
  const applyState = result => {
    status.value = result.status;
    permission.value = result.permission;
    endpoint.value = result.subscription?.endpoint || result.endpoint || null;
  };
  const reportCleanup = result => {
    if (result.cleanupError) alert('PUSH_STALE_CLEANUP_ERROR');
    if (result.serverError) alert('PUSH_UNSUBSCRIBE_ERROR');
  };
  const receiveState = event => {
    if (isPushSessionActive()) applyState(event.detail);
  };

  const refresh = async ({ recoverPermission = false } = {}) => {
    if (!isPushSessionActive() || busy.value) return null;
    if (refreshing) return refreshing;
    const session = pushSession();
    const current = getPushEnvironment();
    const recover =
      recoverPermission ||
      (permission.value === 'denied' && current.permission === 'granted');
    applyState(current);
    if (!current.supported || current.permission !== 'granted') return current;
    status.value = 'checking';
    refreshing = ensurePushSubscription({ recoverPermission: recover });
    try {
      const result = await refreshing;
      if (!mounted || !isCurrentPushSession(session)) return null;
      applyState(result);
      publishBrowserPushState(result);
      reportCleanup(result);
      return result;
    } catch (error) {
      if (mounted && isCurrentPushSession(session)) {
        status.value = 'error';
        alert('PUSH_SUBSCRIPTION_ERROR');
      }
    } finally {
      refreshing = null;
    }
    return null;
  };

  const runAction = async (
    operation,
    errorKey,
    preserveSubscription = false
  ) => {
    if (disabled.value || !isPushSessionActive()) return null;
    const session = pushSession();
    const token = { session };
    activeOperation = token;
    busy.value = true;
    try {
      // Invoke immediately: requestPermission must stay inside the click.
      const result = await operation();
      if (!mounted || !isCurrentPushSession(session)) return null;
      if (result?.status) {
        applyState(result);
        publishBrowserPushState(result);
        reportCleanup(result);
      }
      return result;
    } catch (error) {
      if (mounted && isCurrentPushSession(session)) {
        if (errorKey === 'PUSH_SUBSCRIPTION_ERROR' && !preserveSubscription) {
          const current = getPushEnvironment();
          permission.value = current.permission;
          status.value = current.permission === 'denied' ? 'denied' : 'error';
          endpoint.value = null;
        }
        alert(errorKey);
      }
    } finally {
      if (activeOperation === token) {
        busy.value = false;
        activeOperation = null;
      }
    }
    return null;
  };
  const activate = () =>
    runAction(requestAndSubscribe, 'PUSH_SUBSCRIPTION_ERROR');
  const deactivate = () =>
    runAction(unsubscribePush, 'PUSH_SUBSCRIPTION_ERROR', true);
  const test = () => {
    if (!subscribed.value || !endpoint.value) return null;
    return runAction(async () => {
      await testBrowserSubscription(endpoint.value);
      return { accepted: true };
    }, 'PUSH_TEST_ERROR').then(result => {
      if (result?.accepted && mounted) alert('PUSH_TEST_ACCEPTED');
    });
  };

  onMounted(() => {
    if (activeOperation && !isCurrentPushSession(activeOperation.session)) {
      busy.value = false;
      activeOperation = null;
    }
    window.addEventListener(BROWSER_PUSH_SYNC_EVENT, receiveState);
    refresh();
  });
  onUnmounted(() => {
    mounted = false;
    window.removeEventListener(BROWSER_PUSH_SYNC_EVENT, receiveState);
  });
  return {
    status,
    permission,
    endpoint,
    subscribed,
    busy,
    disabled,
    refresh,
    activate,
    deactivate,
    test,
  };
};
