/* global axios */
import { watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import {
  setPopupRouteResolver,
  closePopupNotification,
  POPUP_DELIVERY_ERROR_EVENT,
} from 'customDashboard/composables/usePopupNotifications';

export const consumeNotificationIntent = async nonce => {
  const registration = await navigator.serviceWorker?.getRegistration('/sw.js');
  if (!registration?.active)
    throw new Error('Notification worker is unavailable');
  return new Promise((resolve, reject) => {
    const channel = new MessageChannel();
    const timeout = setTimeout(() => {
      channel.port1.close();
      reject(new Error('Notification action timed out'));
    }, 10000);
    channel.port1.onmessage = event => {
      clearTimeout(timeout);
      channel.port1.close();
      resolve(event.data);
    };
    registration.active.postMessage(
      { type: 'consume-notification-intent', nonce },
      [channel.port2]
    );
  });
};

export const executeNotificationRead = async (intent, store) => {
  const user = store.getters.getCurrentUser;
  if (!user?.id || String(user.id) !== String(intent?.user_id))
    throw new Error('Notification recipient does not match this session');
  if (
    !['account_id', 'notification_id'].every(key =>
      /^[1-9]\d*$/.test(String(intent[key]))
    )
  )
    throw new Error('Invalid notification action');
  const { data } = await axios.post(
    `/api/v1/accounts/${intent.account_id}/notification_actions/${intent.notification_id}/read`,
    {},
    { timeout: 10000 }
  );
  // Do not apply an old request's result to another user's session.
  if (String(store.getters.getCurrentUser?.id) !== String(user.id))
    return undefined;
  closePopupNotification(data.account_id, data.id);
  if (String(store.getters.getCurrentAccountId) === String(data.account_id)) {
    await store.dispatch('notifications/unReadCount');
    await store.dispatch('notifications/index');
  }
  return data;
};

export const startNotificationActions = (router, store, t) => {
  setPopupRouteResolver(() => router.currentRoute.value);
  let processing = false;
  let deliveryErrorShown = false;
  const reportDeliveryError = () => {
    if (deliveryErrorShown) return;
    deliveryErrorShown = true;
    useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.POPUP_DELIVERY_ERROR'));
  };
  window.addEventListener(POPUP_DELIVERY_ERROR_EVENT, reportDeliveryError);
  const stop = watch(
    () => [
      router.currentRoute.value.query.notification_intent,
      store.getters.getCurrentUser?.id,
      store.getters.getAuthUIFlags?.isFetching,
    ],
    async ([nonce, userId, fetching]) => {
      if (!nonce || processing || fetching) return;
      processing = true;
      try {
        await router.replace({
          query: {
            ...router.currentRoute.value.query,
            notification_intent: undefined,
          },
        });
        const intent = await consumeNotificationIntent(nonce);
        // Always consume the intent, including when login is required. Never
        // persist it for automatic execution after a subsequent login.
        if (!userId) {
          useAlert(
            t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.ACTION_LOGIN_REQUIRED')
          );
          await router.push({ name: 'login' });
          return;
        }
        if (!intent) throw new Error('Notification action expired');
        await executeNotificationRead(intent, store);
      } catch (error) {
        useAlert(t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.ACTION_READ_ERROR'));
      } finally {
        processing = false;
      }
    },
    { immediate: true }
  );
  return () => {
    stop();
    window.removeEventListener(POPUP_DELIVERY_ERROR_EVENT, reportDeliveryError);
    setPopupRouteResolver(() => null);
  };
};
