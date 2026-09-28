/* global axios */
import ApiClient from './ApiClient';

class NotificationSubscriptions extends ApiClient {
  constructor() {
    super('notification_subscriptions');
  }

  destroyBrowserSubscription(endpoint) {
    return axios.delete(this.url, {
      params: { endpoint },
    });
  }
}

export default new NotificationSubscriptions();
