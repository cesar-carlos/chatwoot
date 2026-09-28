/* eslint-disable no-restricted-globals */
/* globals clients */
self.addEventListener('push', event => {
  const notification = event.data.json();

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

self.addEventListener('notificationclick', event => {
  const { notification } = event;
  notification.close();

  event.waitUntil(
    (async () => {
      const targetUrl = new URL(notification.data.url, self.location.origin)
        .href;
      const windowClients = await clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      const sameOriginClient = windowClients.find(
        client => new URL(client.url).origin === self.location.origin
      );

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
