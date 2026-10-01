/* global axios */
import NotificationSubscriptions from 'dashboard/api/notificationSubscription';
import { pushRequest } from 'customDashboard/helper/pushSession';

const DELETE_TIMEOUT_MS = 10000;

export const destroyBrowserSubscription = (endpoint, options = {}) =>
  axios.delete(NotificationSubscriptions.url, {
    params: { endpoint },
    timeout: DELETE_TIMEOUT_MS,
    ...options,
  });

export const synchronizeBrowserSubscription = payload =>
  pushRequest(options =>
    axios.post(NotificationSubscriptions.url, payload, options)
  );

export const testBrowserSubscription = endpoint =>
  pushRequest(options =>
    axios.post(`${NotificationSubscriptions.url}/test`, { endpoint }, options)
  );
