import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import {
  ensurePushSubscription,
  getPushEnvironment,
  isPushOptedOut,
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
import { classifyPushDiagnosticError } from 'customDashboard/helper/pushDiagnostic';

// One action lock for every surface; a click must not open a second prompt.
const busy = ref(false);
const activity = ref(null);
let activeOperation;
const translationPrefix = 'PROFILE_SETTINGS.FORM.NOTIFICATIONS.';

export const usePushDevice = () => {
  const { t } = useI18n();
  const environment = getPushEnvironment();
  const permission = ref(environment.permission);
  const reason = ref(environment.reason || null);
  const status = ref(
    environment.supported && permission.value === 'granted'
      ? 'checking'
      : environment.status
  );
  const endpoint = ref(null);
  let mounted = true;
  const instanceSession = isPushSessionActive() ? pushSession() : null;
  const live = () =>
    mounted && instanceSession && isCurrentPushSession(instanceSession);
  const subscribed = computed(() => status.value === 'subscribed');
  const disabled = computed(() => busy.value || status.value === 'checking');
  const alert = key => useAlert(t(`${translationPrefix}${key}`));
  const applyState = result => {
    status.value = result.status;
    permission.value = result.permission;
    reason.value = result.reason || null;
    endpoint.value = result.subscription?.endpoint || result.endpoint || null;
  };
  const reportCleanup = result => {
    if (result.cleanupError) alert('PUSH_STALE_CLEANUP_ERROR');
    if (result.serverError) alert('PUSH_UNSUBSCRIBE_ERROR');
  };
  const receiveState = event => {
    if (live()) applyState(event.detail);
  };

  const runAction = async (
    operation,
    errorKey,
    preserveSubscription = false,
    activityName = 'activating'
  ) => {
    if (!live() || busy.value) return null;
    const session = pushSession();
    const token = { session };
    activeOperation = token;
    busy.value = true;
    activity.value = activityName;
    try {
      // Invoke immediately: requestPermission must stay inside the click.
      const result = await operation(session);
      if (!mounted || !isCurrentPushSession(session)) return null;
      if (result?.status) {
        applyState(result);
        publishBrowserPushState(result);
        reportCleanup(result);
      }
      return result;
    } catch (error) {
      if (mounted && isCurrentPushSession(session)) {
        if (!errorKey) {
          if (status.value === 'checking') status.value = 'error';
          return classifyPushDiagnosticError(error);
        }
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
        activity.value = null;
        activeOperation = null;
      }
    }
    return null;
  };
  const activate = () =>
    runAction(requestAndSubscribe, 'PUSH_SUBSCRIPTION_ERROR');
  const deactivate = () =>
    runAction(unsubscribePush, 'PUSH_SUBSCRIPTION_ERROR', true, 'deactivating');
  const refresh = ({ recoverPermission = false } = {}) => {
    if (!live() || busy.value) return Promise.resolve(null);
    const current = getPushEnvironment();
    const recover =
      recoverPermission ||
      (permission.value === 'denied' && current.permission === 'granted');
    if (!current.supported || current.permission !== 'granted') {
      applyState(current);
      return Promise.resolve(current);
    }
    return runAction(
      () => {
        applyState(current);
        status.value = 'checking';
        return ensurePushSubscription({ recoverPermission: recover });
      },
      'PUSH_SUBSCRIPTION_ERROR',
      false,
      'checking'
    );
  };

  const preflight = async (session, recoverPermission) => {
    let current = getPushEnvironment();
    applyState(current);
    if (!current.supported || current.permission !== 'granted')
      return { kind: current.reason || current.status };
    if (isPushOptedOut()) {
      status.value = 'unsubscribed';
      return { kind: 'opt_out' };
    }
    status.value = 'checking';
    const result = await ensurePushSubscription({ recoverPermission });
    if (!mounted || !isCurrentPushSession(session)) return null;
    // Permission or opt-out may change while the worker/server was awaited.
    current = getPushEnvironment();
    if (!current.supported || current.permission !== 'granted') {
      applyState(current);
      return { kind: current.reason || current.status };
    }
    if (isPushOptedOut()) {
      applyState({ ...current, status: 'unsubscribed' });
      return { kind: 'opt_out' };
    }
    applyState(result);
    publishBrowserPushState(result);
    reportCleanup(result);
    return {
      kind: subscribed.value && endpoint.value ? 'ready' : 'missing',
      endpoint: endpoint.value,
    };
  };
  const inspect = ({ recoverPermission = false } = {}) =>
    runAction(
      session => preflight(session, recoverPermission),
      null,
      false,
      'checking'
    );
  const test = () =>
    runAction(
      async session => {
        const checked = await preflight(session, false);
        if (checked?.kind !== 'ready') return checked;
        activity.value = 'testing';
        const response = await testBrowserSubscription(checked.endpoint);
        if (!mounted || !isCurrentPushSession(session)) return null;
        const current = getPushEnvironment();
        if (!current.supported || current.permission !== 'granted') {
          applyState(current);
          return { kind: current.reason || current.status };
        }
        if (isPushOptedOut()) {
          applyState({ ...current, status: 'unsubscribed' });
          return { kind: 'opt_out' };
        }
        return response.data?.accepted === true
          ? { kind: 'accepted' }
          : { kind: 'delivery' };
      },
      null,
      false,
      'checking'
    );

  onMounted(() => {
    if (activeOperation && !isCurrentPushSession(activeOperation.session)) {
      busy.value = false;
      activity.value = null;
      activeOperation = null;
    }
    window.addEventListener(BROWSER_PUSH_SYNC_EVENT, receiveState);
    refresh();
  });
  watch(busy, value => {
    // Another surface may have unmounted before publishing its initial check.
    if (!value && status.value === 'checking' && live()) refresh();
  });
  onUnmounted(() => {
    mounted = false;
    window.removeEventListener(BROWSER_PUSH_SYNC_EVENT, receiveState);
  });
  return {
    status,
    permission,
    reason,
    activity,
    endpoint,
    subscribed,
    busy,
    disabled,
    refresh,
    activate,
    deactivate,
    test,
    inspect,
  };
};
