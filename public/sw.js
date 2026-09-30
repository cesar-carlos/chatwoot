/* eslint-disable no-restricted-globals */
/* globals clients */
self.addEventListener('push', event => {
  let notification;
  try {
    notification = event.data?.json();
  } catch (error) {
    return;
  }

  if (!notification || typeof notification.title !== 'string') return;

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      body: notification.body,
      icon: notification.icon,
      tag: notification.tag,
      data: {
        url: notification.url,
      },
    })
  );
});

const safeTargetUrl = rawUrl => {
  try {
    const targetUrl = new URL(rawUrl || '/', self.location.origin);
    return targetUrl.origin === self.location.origin
      ? targetUrl.href
      : new URL('/', self.location.origin).href;
  } catch (error) {
    return new URL('/', self.location.origin).href;
  }
};

const belongsToCurrentOrigin = client => {
  try {
    return new URL(client.url).origin === self.location.origin;
  } catch (error) {
    return false;
  }
};

self.addEventListener('notificationclick', event => {
  const { notification } = event;
  notification.close();

  event.waitUntil(
    (async () => {
      const targetUrl = safeTargetUrl(notification.data?.url);
      const windowClients = await clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      const sameOriginClient = windowClients.find(belongsToCurrentOrigin);

      if (sameOriginClient) {
        if ('navigate' in sameOriginClient) {
          await sameOriginClient.navigate(targetUrl);
        }
        return sameOriginClient.focus();
      }

      return clients.openWindow(targetUrl);
    })()
  );
});
