import NotificationSubscriptions from '../api/notificationSubscription';
import auth from '../api/auth';

const PUSH_STATUS = {
  UNSUPPORTED: 'unsupported',
  REQUIRES_INSTALL: 'requires_install',
  DEFAULT: 'default',
  DENIED: 'denied',
  SUBSCRIBED: 'subscribed',
  UNSUBSCRIBED: 'unsubscribed',
};

const isIosDevice = () =>
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

const isStandalone = () =>
  window.matchMedia('(display-mode: standalone)').matches ||
  navigator.standalone === true;

export const getPushEnvironment = () => {
  const permission =
    'Notification' in window ? Notification.permission : PUSH_STATUS.DEFAULT;

  if (isIosDevice() && !isStandalone()) {
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
    Boolean(window.chatwootConfig.vapidPublicKey);

  return {
    supported,
    status: supported ? permission : PUSH_STATUS.UNSUPPORTED,
    permission,
  };
};

const registerServiceWorker = () => navigator.serviceWorker.register('/sw.js');

const currentApplicationServerKey = () => {
  const key = window.chatwootConfig.vapidPublicKey;
  if (typeof key !== 'string') {
    return new Uint8Array(key);
  }

  const padding = '='.repeat((4 - (key.length % 4)) % 4);
  const base64 = (key + padding).replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(base64), character => character.charCodeAt(0));
};

const subscriptionUsesCurrentKey = subscription => {
  const subscriptionKey = subscription.options.applicationServerKey;
  if (!subscriptionKey) {
    return false;
  }

  const actual = new Uint8Array(subscriptionKey);
  const expected = currentApplicationServerKey();
  return (
    actual.length === expected.length &&
    actual.every((value, index) => value === expected[index])
  );
};

const generateKeys = str =>
  btoa(String.fromCharCode.apply(null, new Uint8Array(str)))
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
  if (!auth.hasAuthCookie()) {
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
    applicationServerKey: window.chatwootConfig.vapidPublicKey,
  });

const synchronizePushSubscription = async environment => {
  const registration = await registerServiceWorker();
  let subscription = await registration.pushManager.getSubscription();

  if (subscription && !subscriptionUsesCurrentKey(subscription)) {
    await NotificationSubscriptions.destroyBrowserSubscription(
      subscription.endpoint
    );
    const removed = await subscription.unsubscribe();
    if (!removed) {
      throw new Error('The browser did not remove the stale push subscription');
    }
    subscription = null;
  }

  if (!subscription) {
    subscription = await subscribe(registration);
  }
  await sendRegistrationToServer(subscription);

  return {
    ...environment,
    status: PUSH_STATUS.SUBSCRIBED,
    subscription,
  };
};

export const ensurePushSubscription = async () => {
  const environment = getPushEnvironment();
  if (!environment.supported || environment.permission !== 'granted') {
    return environment;
  }

  return synchronizePushSubscription(environment);
};

export const requestAndSubscribe = async () => {
  const environment = getPushEnvironment();
  if (!environment.supported) {
    return environment;
  }

  const permission =
    environment.permission === PUSH_STATUS.DEFAULT
      ? await Notification.requestPermission()
      : environment.permission;

  if (permission !== 'granted') {
    return { ...environment, status: permission, permission };
  }

  return synchronizePushSubscription({
    ...environment,
    status: permission,
    permission,
  });
};

export const unsubscribePush = async () => {
  const environment = getPushEnvironment();
  if (!environment.supported) {
    return environment;
  }

  const registration = await registerServiceWorker();
  const subscription = await registration.pushManager.getSubscription();
  if (!subscription) {
    return { ...environment, status: PUSH_STATUS.UNSUBSCRIBED };
  }

  let serverError;
  try {
    await NotificationSubscriptions.destroyBrowserSubscription(
      subscription.endpoint
    );
  } catch (error) {
    serverError = error;
  }

  const removedLocally = await subscription.unsubscribe();
  if (!removedLocally) {
    throw new Error('The browser did not remove the push subscription');
  }

  return {
    ...environment,
    status: PUSH_STATUS.UNSUBSCRIBED,
    serverError,
  };
};
