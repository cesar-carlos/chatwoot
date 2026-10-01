/* global axios */
import NotificationSubscriptions from 'dashboard/api/notificationSubscription';

const DELETE_TIMEOUT_MS = 10000;

export const destroyBrowserSubscription = endpoint =>
  axios.delete(NotificationSubscriptions.url, {
    params: { endpoint },
    timeout: DELETE_TIMEOUT_MS,
  });
