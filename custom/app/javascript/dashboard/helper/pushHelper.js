import NotificationSubscriptions from 'dashboard/api/notificationSubscription';
import Cookies from 'js-cookie';
import { destroyBrowserSubscription } from 'customDashboard/api/notificationSubscription';

export const PUSH_STATUS = {
  UNSUPPORTED: 'unsupported',
  REQUIRES_INSTALL: 'requires_install',
  DEFAULT: 'default',
  DENIED: 'denied',
  SUBSCRIBED: 'subscribed',
  UNSUBSCRIBED: 'unsubscribed',
};

const PUSH_ENABLED_STORAGE_KEY = 'chatwoot_push_enabled';
let pendingOperation = Promise.resolve();

const enqueueOperation = operation => {
  const result = pendingOperation.then(operation, operation);
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

const registerServiceWorker = () =>
  navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' });

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

export const sendRegistrationToServer = async subscription => {
  if (!Cookies.get('cw_d_session_info')) {
    throw new Error(
      'Cannot synchronize a push subscription without authentication'
    );
  }

  return NotificationSubscriptions.create(
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
  currentSubscription
) => {
  const registration =
    serviceWorkerRegistration || (await registerServiceWorker());
  let subscription =
    currentSubscription ?? (await registration.pushManager.getSubscription());
  let cleanupError;

  if (subscription && !subscriptionUsesCurrentKey(subscription)) {
    try {
      await destroyBrowserSubscription(subscription.endpoint);
    } catch (error) {
      cleanupError = error;
    }

    const removed = await subscription.unsubscribe();
    if (!removed) {
      throw new Error('The browser did not remove the stale push subscription');
    }
    subscription = null;
  }

  if (!subscription) subscription = await subscribe(registration);
  await sendRegistrationToServer(subscription);

  return {
    ...environment,
    status: PUSH_STATUS.SUBSCRIBED,
    subscription,
    cleanupError,
  };
};

const ensurePushSubscriptionOperation = async () => {
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
  if (pushPreference === null && !subscription) {
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  const result = await synchronizePushSubscription(
    environment,
    registration,
    subscription
  );
  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'true');
  return result;
};

export const ensurePushSubscription = () =>
  enqueueOperation(ensurePushSubscriptionOperation);

const requestAndSubscribeOperation = async () => {
  const environment = getPushEnvironment();
  if (!environment.supported) return environment;

  const permission =
    environment.permission === PUSH_STATUS.DEFAULT
      ? await Notification.requestPermission()
      : environment.permission;

  if (permission !== 'granted') {
    return { ...environment, status: permission, permission };
  }

  const result = await synchronizePushSubscription({
    ...environment,
    status: permission,
    permission,
  });
  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'true');
  return result;
};

export const requestAndSubscribe = () =>
  enqueueOperation(requestAndSubscribeOperation);

const unsubscribePushOperation = async () => {
  const environment = getPushEnvironment();
  if (!('serviceWorker' in navigator)) {
    localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  const registration = await navigator.serviceWorker.getRegistration('/sw.js');
  const subscription = await registration?.pushManager.getSubscription();
  if (!subscription) {
    localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  let serverError;
  try {
    await destroyBrowserSubscription(subscription.endpoint);
  } catch (error) {
    serverError = error;
  }

  const removedLocally = await subscription.unsubscribe();
  if (!removedLocally) {
    throw new Error('The browser did not remove the push subscription');
  }

  localStorage.setItem(PUSH_ENABLED_STORAGE_KEY, 'false');
  return {
    ...environment,
    status: PUSH_STATUS.UNSUBSCRIBED,
    serverError,
  };
};

export const unsubscribePush = () => enqueueOperation(unsubscribePushOperation);
