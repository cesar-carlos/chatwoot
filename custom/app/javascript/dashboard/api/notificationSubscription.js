/* global axios */
import NotificationSubscriptions from 'dashboard/api/notificationSubscription';

export const destroyBrowserSubscription = endpoint =>
  axios.delete(NotificationSubscriptions.url, { params: { endpoint } });
