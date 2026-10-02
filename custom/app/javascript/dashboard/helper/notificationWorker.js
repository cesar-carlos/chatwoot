/* eslint-disable no-restricted-globals */
/* globals clients */
const pendingIntents = new Map();
const NOTIFICATION_INTENT_TTL_MS = 60000;
// Content-free fallback: malformed messages must not become silent pushes on iOS.
const FALLBACK_NOTIFICATION = {
  title: 'New notification',
  body: 'Open the app to view your notifications.',
  url: '/app',
};
const pendingNotifications = new Map();
const noticeKey = data => `${data.account_id}:${data.notification_id}`;
const positiveId = value =>
  /^[1-9]\d*$/.test(String(value)) && Number.isSafeInteger(Number(value));

const safeTargetUrl = rawUrl => {
  try {
    const url = new URL(rawUrl || '/', self.location.origin);
    if (url.origin === self.location.origin) return url.href;
  } catch (error) {
    // Invalid or cross-origin payloads never navigate away from the installation.
  }
  return new URL('/', self.location.origin).href;
};
const dashboardAccountId = rawUrl => {
  try {
    return new URL(rawUrl).pathname.match(
      /^\/app\/accounts\/(\d+)(?:\/|$)/
    )?.[1];
  } catch (error) {
    return null;
  }
};
const realNotification = data =>
  ['user_id', 'account_id', 'notification_id'].every(key =>
    positiveId(data[key])
  ) && dashboardAccountId(safeTargetUrl(data.url)) === String(data.account_id);

self.addEventListener('push', event => {
  let data;
  try {
    data = event.data?.json();
  } catch (error) {
    data = null;
  }
  if (!data || typeof data.title !== 'string' || !data.title.trim()) {
    data = FALLBACK_NOTIFICATION;
    // eslint-disable-next-line no-console
    console.warn('Push notification fallback result=invalid_payload');
  }
  const actions = realNotification(data)
    ? [
        {
          action: 'open_conversation',
          title: data.action_labels?.open || 'Open conversation',
        },
        {
          action: 'mark_read',
          title: data.action_labels?.read || 'Mark as read',
        },
      ].slice(0, self.Notification?.maxActions ?? 0)
    : [];
  const pending = { data, dismissed: false };
  pendingNotifications.set(noticeKey(data), pending);
  event.waitUntil(
    (async () => {
      try {
        const options = {
          body: typeof data.body === 'string' ? data.body : undefined,
          icon: typeof data.icon === 'string' ? data.icon : undefined,
          tag: typeof data.tag === 'string' ? data.tag : undefined,
          actions,
          data: {
            url: safeTargetUrl(data.url),
            user_id: data.user_id,
            account_id: data.account_id,
            notification_id: data.notification_id,
            conversation_id: new URL(safeTargetUrl(data.url)).pathname.match(
              /\/conversations\/(\d+)(?:\/|$)/
            )?.[1],
          },
        };
        try {
          await self.registration.showNotification(data.title, options);
        } catch (error) {
          // Remove optional fields and actions if the normal display failed.
          // eslint-disable-next-line no-console
          console.warn('Push notification fallback result=display_failed');
          await self.registration.showNotification(
            FALLBACK_NOTIFICATION.title,
            {
              body: FALLBACK_NOTIFICATION.body,
              data: { url: safeTargetUrl(FALLBACK_NOTIFICATION.url) },
            }
          );
        }
        if (pending.dismissed) {
          const notifications = await self.registration.getNotifications({
            tag: data.tag,
          });
          notifications
            .filter(
              notification =>
                noticeKey(notification.data || {}) === noticeKey(data)
            )
            .forEach(notification => notification.close());
        }
      } finally {
        if (pendingNotifications.get(noticeKey(data)) === pending)
          pendingNotifications.delete(noticeKey(data));
      }
    })()
  );
});

const openConversation = async targetUrl => {
  try {
    const windows = await clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    const dashboardClients = windows.filter(client => {
      const url = new URL(client.url);
      return (
        url.origin === self.location.origin &&
        (url.pathname === '/app' || url.pathname.startsWith('/app/'))
      );
    });
    const accountId = dashboardAccountId(targetUrl);
    const client =
      dashboardClients.find(
        candidate => dashboardAccountId(candidate.url) === accountId
      ) ||
      dashboardClients.find(
        candidate => new URL(candidate.url).pathname === '/app'
      ) ||
      (dashboardClients.length === 1 ? dashboardClients[0] : null);
    if (client?.navigate && client.focus) {
      const navigated = await client.navigate(targetUrl);
      if (!navigated) throw new Error('Notification client disappeared');
      const focused = await navigated.focus();
      if (!focused) throw new Error('Notification client could not be focused');
      return focused;
    }
  } catch (error) {
    // A closed client, failed navigation or failed focus must not lose the click.
  }
  return clients.openWindow(targetUrl);
};

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const data = event.notification.data || {};
  const url = new URL(safeTargetUrl(data.url));
  if (event.action === 'mark_read' && realNotification(data)) {
    // A one-use in-memory intent is not an authentication credential. Arbitrary
    // external URLs cannot trigger a write by guessing recipient IDs.
    const nonce = self.crypto.randomUUID();
    pendingIntents.set(nonce, {
      ...data,
      expires: Date.now() + NOTIFICATION_INTENT_TTL_MS,
    });
    setTimeout(() => pendingIntents.delete(nonce), NOTIFICATION_INTENT_TTL_MS);
    // Opening a conversation updates last-seen and would read other notices.
    url.pathname = `/app/accounts/${data.account_id}/inbox-view`;
    url.search = '';
    url.hash = '';
    url.searchParams.set('notification_intent', nonce);
  }
  event.waitUntil(openConversation(url.href));
});

self.addEventListener('message', event => {
  if (event.data?.type === 'notifications-read') {
    const receipt = event.data.receipt;
    if (!receipt || !positiveId(receipt.account_id)) return;
    const matches = data =>
      String(data.account_id) === String(receipt.account_id) &&
      (!receipt.user_id || String(data.user_id) === String(receipt.user_id)) &&
      (receipt.notification_id
        ? String(data.notification_id) === String(receipt.notification_id)
        : positiveId(receipt.through_notification_id) &&
          Number(data.notification_id) <=
            Number(receipt.through_notification_id)) &&
      (!receipt.conversation_display_id ||
        String(
          new URL(safeTargetUrl(data.url)).pathname.match(
            /\/conversations\/(\d+)(?:\/|$)/
          )?.[1]
        ) === String(receipt.conversation_display_id));
    pendingNotifications.forEach(pending => {
      if (matches(pending.data)) pending.dismissed = true;
    });
    return;
  }
  if (event.data?.type !== 'consume-notification-intent') return;
  const nonce = event.data.nonce;
  const intent = pendingIntents.get(nonce);
  pendingIntents.delete(nonce);
  const sourceUrl = event.source?.url && safeTargetUrl(event.source.url);
  const valid =
    intent &&
    intent.expires >= Date.now() &&
    sourceUrl &&
    new URL(sourceUrl).origin === self.location.origin &&
    dashboardAccountId(sourceUrl) === String(intent.account_id);
  event.ports[0]?.postMessage(valid ? intent : null);
});
