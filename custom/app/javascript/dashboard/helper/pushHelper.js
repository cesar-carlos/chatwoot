import Cookies from 'js-cookie';
import {
  destroyBrowserSubscription,
  synchronizeBrowserSubscription,
} from 'customDashboard/api/notificationSubscription';
import {
  assertPushSession,
  pushSession,
  beginPushLogout,
  pushRequest,
  PUSH_OPERATION_TIMEOUT_MS,
} from './pushSession';
import { waitForActiveWorker } from './serviceWorker';

export const PUSH_STATUS = {
  UNSUPPORTED: 'unsupported',
  REQUIRES_INSTALL: 'requires_install',
  DEFAULT: 'default',
  DENIED: 'denied',
  SUBSCRIBED: 'subscribed',
  UNSUBSCRIBED: 'unsubscribed',
};

const PUSH_ENABLED_STORAGE_KEY = 'chatwoot_push_enabled';
export const isPushOptedOut = () =>
  localStorage.getItem(PUSH_ENABLED_STORAGE_KEY) === 'false';
let pendingOperation = Promise.resolve();

const enqueueOperation = operation => {
  const session = pushSession();
  const run = () => {
    assertPushSession(session);
    return operation(session);
  };
  const result = pendingOperation.then(run, run);
  pendingOperation = result.catch(() => {});
  return result;
};

const isIosDevice = () =>
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

export const isPwaStandalone = () =>
  window.matchMedia('(display-mode: standalone)').matches ||
  navigator.standalone === true;

export const getPushEnvironment = () => {
  const permission =
    'Notification' in window ? Notification.permission : PUSH_STATUS.DEFAULT;

  if (isIosDevice() && !isPwaStandalone()) {
    return {
      supported: false,
      status: PUSH_STATUS.REQUIRES_INSTALL,
      permission,
    };
  }

  const supported =
    window.isSecureContext &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window &&
    Boolean(window.chatwootConfig?.vapidPublicKey);

  return {
    supported,
    status: supported ? permission : PUSH_STATUS.UNSUPPORTED,
    permission,
  };
};

const registerServiceWorker = async () =>
  waitForActiveWorker(
    await navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' })
  );

const currentApplicationServerKey = () => {
  const key = window.chatwootConfig.vapidPublicKey;
  if (typeof key !== 'string') return new Uint8Array(key);

  const padding = '='.repeat((4 - (key.length % 4)) % 4);
  const base64 = (key + padding).replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(base64), character => character.charCodeAt(0));
};

const subscriptionUsesCurrentKey = subscription => {
  const subscriptionKey = subscription.options?.applicationServerKey;
  if (!subscriptionKey) return false;

  const actual = new Uint8Array(subscriptionKey);
  const expected = currentApplicationServerKey();
  return (
    actual.length === expected.length &&
    actual.every((value, index) => value === expected[index])
  );
};

const generateKeys = value =>
  btoa(String.fromCharCode.apply(null, new Uint8Array(value)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

export const getPushSubscriptionPayload = subscription => ({
  subscription_type: 'browser_push',
  subscription_attributes: {
    endpoint: subscription.endpoint,
    p256dh: generateKeys(subscription.getKey('p256dh')),
    auth: generateKeys(subscription.getKey('auth')),
  },
});

export const sendRegistrationToServer = async (
  subscription,
  session = pushSession()
) => {
  assertPushSession(session);
  if (!Cookies.get('cw_d_session_info')) {
    throw new Error(
      'Cannot synchronize a push subscription without authentication'
    );
  }

  return synchronizeBrowserSubscription(
    getPushSubscriptionPayload(subscription)
  );
};

const subscribe = registration =>
  registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: currentApplicationServerKey(),
  });

const synchronizePushSubscription = async (
  environment,
  serviceWorkerRegistration,
  currentSubscription,
  session
) => {
  const registration =
    serviceWorkerRegistration || (await registerServiceWorker());
  let subscription =
    currentSubscription ?? (await registration.pushManager.getSubscription());
  let cleanupError;
  assertPushSession(session);

  if (subscription && !subscriptionUsesCurrentKey(subscription)) {
    try {
      await pushRequest(options =>
        destroyBrowserSubscription(subscription.endpoint, options)
      );
    } catch (error) {
      cleanupError = error;
    }

    assertPushSession(session);
    const removed = await subscription.unsubscribe();
    if (!removed) {
      throw new Error('The browser did not remove the stale push subscription');
    }
    subscription = null;
  }

  assertPushSession(session);
  if (!subscription) {
    subscription = await subscribe(registration);
    try {
      assertPushSession(session);
    } catch (error) {
      await subscription.unsubscribe();
      throw error;
    }
  }
  await sendRegistrationToServer(subscription, session);
  assertPushSession(session);

  return {
    ...environment,
    status: PUSH_STATUS.SUBSCRIBED,
    subscription,
    cleanupError,
  };
};

const ensurePushSubscriptionOperation = async (session, recoverPermission) => {
  const environment = getPushEnvironment();
  if (!environment.supported || environment.permission !== 'granted') {
    return environment;
  }

  const pushPreference = localStorage.getItem(PUSH_ENABLED_STORAGE_KEY);
  if (pushPreference === 'false') {
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  const registration = await registerServiceWorker();
  const subscription = await registration.pushManager.getSubscription();
  assertPushSession(session);
  if (pushPreference === null && !subscription && !recoverPermission) {
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  const result = await synchronizePushSubscription(
    environment,
    registration,
    subscription,
    session
  );
  assertPushSession(session);
  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'true');
  return result;
};

export const ensurePushSubscription = ({ recoverPermission = false } = {}) =>
  enqueueOperation(session =>
    ensurePushSubscriptionOperation(session, recoverPermission)
  );

const requestAndSubscribeOperation = async (
  session,
  environment,
  permissionRequest
) => {
  if (!environment.supported) return environment;

  const permission = await permissionRequest;

  if (permission !== 'granted') {
    return { ...environment, status: permission, permission };
  }

  assertPushSession(session);
  const result = await synchronizePushSubscription(
    {
      ...environment,
      status: permission,
      permission,
    },
    null,
    null,
    session
  );
  assertPushSession(session);
  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'true');
  return result;
};

export const requestAndSubscribe = () => {
  pushSession();
  const environment = getPushEnvironment();
  // Start the permission prompt during the click, not after a queued sync.
  const permission =
    environment.supported && environment.permission === PUSH_STATUS.DEFAULT
      ? Notification.requestPermission()
      : Promise.resolve(environment.permission);
  return enqueueOperation(session =>
    requestAndSubscribeOperation(session, environment, permission)
  );
};

const unsubscribePushOperation = async session => {
  const environment = getPushEnvironment();
  if (!('serviceWorker' in navigator)) {
    localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  const registration = await navigator.serviceWorker.getRegistration('/sw.js');
  const subscription = await registration?.pushManager.getSubscription();
  assertPushSession(session);
  if (!subscription) {
    localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  let serverError;
  try {
    await pushRequest(options =>
      destroyBrowserSubscription(subscription.endpoint, options)
    );
  } catch (error) {
    serverError = error;
  }

  assertPushSession(session);
  const removedLocally = await subscription.unsubscribe();
  if (!removedLocally) {
    throw new Error('The browser did not remove the push subscription');
  }
  assertPushSession(session);
  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
  return {
    ...environment,
    status: PUSH_STATUS.UNSUBSCRIBED,
    serverError,
  };
};

export const unsubscribePush = () => enqueueOperation(unsubscribePushOperation);

// Logout bypasses the synchronization queue and cancels its network requests.
export const cleanupPushOnLogout = async () => {
  beginPushLogout();
  pendingOperation = Promise.resolve();
  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
  const controller = new AbortController();
  let timeout;
  const cleanup = (async () => {
    if (!('serviceWorker' in navigator)) return {};
    const registration =
      await navigator.serviceWorker.getRegistration('/sw.js');
    if (controller.signal.aborted) return {};
    const subscription = await registration?.pushManager.getSubscription();
    if (!subscription || controller.signal.aborted) return {};
    // Attempt local cancellation even if remote deletion never completes.
    const results = await Promise.allSettled([
      subscription.unsubscribe(),
      destroyBrowserSubscription(subscription.endpoint, {
        signal: controller.signal,
      }),
    ]);
    return {
      serverError: results.find(result => result.status === 'rejected'),
    };
  })();
  try {
    return await Promise.race([
      cleanup,
      new Promise((resolve, reject) => {
        timeout = setTimeout(() => {
          controller.abort();
          reject(new Error('Push logout cleanup timed out'));
        }, PUSH_OPERATION_TIMEOUT_MS);
      }),
    ]);
  } finally {
    clearTimeout(timeout);
    controller.abort();
  }
};
