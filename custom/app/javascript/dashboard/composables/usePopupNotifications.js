import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

const DEFAULT_ICON = '/brand-assets/logo_thumbnail.svg';
const SKIPPED_POPUP_TYPES = new Set(['voice_call_incoming']);
export const POPUP_FLAGS_BY_ACCOUNT_KEY = 'popup_notification_flags_by_account';
const LEGACY_POPUP_FLAGS_KEY = 'popup_notification_flags';

const openPopups = new Map();
const popupKey = (accountId, conversationId) =>
  `${accountId}:${conversationId}`;

export const popupFlagFor = notificationType => `popup_${notificationType}`;

export const supportsPopupNotificationType = notificationType =>
  Boolean(notificationType) && !SKIPPED_POPUP_TYPES.has(notificationType);

export const popupFlagsForSettings = (uiSettings, accountId) => {
  const settings = uiSettings || {};
  const id = String(accountId ?? '');
  const byAccount = settings[POPUP_FLAGS_BY_ACCOUNT_KEY];
  if (id && byAccount && Array.isArray(byAccount[id])) return byAccount[id];
  if (!byAccount && Array.isArray(settings[LEGACY_POPUP_FLAGS_KEY])) {
    return settings[LEGACY_POPUP_FLAGS_KEY];
  }
  return [];
};

export const withPopupFlagsForAccount = (uiSettings, accountId, flags) => {
  const next = { ...(uiSettings || {}) };
  delete next[LEGACY_POPUP_FLAGS_KEY];
  return {
    ...next,
    [POPUP_FLAGS_BY_ACCOUNT_KEY]: {
      ...(uiSettings?.[POPUP_FLAGS_BY_ACCOUNT_KEY] || {}),
      [String(accountId)]: flags,
    },
  };
};

export const getPopupNotificationFlags = (store, accountId) =>
  popupFlagsForSettings(
    store?.getters?.getUISettings,
    accountId ?? store?.getters?.getCurrentAccountId
  );

export const isPopupNotificationEnabled = (
  notificationType,
  store,
  accountId
) => {
  if (!supportsPopupNotificationType(notificationType)) return false;
  return getPopupNotificationFlags(store, accountId).includes(
    popupFlagFor(notificationType)
  );
};

export const requestPopupNotificationPermission = () => {
  if (typeof Notification === 'undefined') {
    return Promise.resolve('unsupported');
  }
  if (Notification.permission === 'granted') return Promise.resolve('granted');
  if (Notification.permission === 'denied') return Promise.resolve('denied');
  return Notification.requestPermission();
};

export const popupMessageBody = (body, senderName) => {
  const text = body || '';
  const prefix = senderName ? `${senderName}: ` : '';
  if (prefix && text.startsWith(prefix)) return text.slice(prefix.length);
  return text;
};

export const isViewingConversation = (accountId, conversationId) => {
  if (document.visibilityState !== 'visible') return false;
  if (conversationId == null || conversationId === '') return false;
  const path = window.location.pathname || '';
  return new RegExp(
    `/accounts/${accountId}/conversations/${conversationId}(?:/|$)`
  ).test(path);
};

const conversationFromNotification = notification => {
  const primaryActor = notification?.primary_actor || {};
  const sender = primaryActor.meta?.sender || {};
  return {
    conversationId: primaryActor.id,
    senderName: sender.name || '',
    icon: sender.thumbnail || DEFAULT_ICON,
  };
};

const navigateToConversation = (accountId, conversationId) => {
  if (!accountId || !conversationId) return;
  const path = frontendURL(conversationUrl({ accountId, id: conversationId }));
  import('dashboard/routes').then(({ router }) => {
    router.push({ path });
  });
};

const rememberPopup = (accountId, conversationId, nativeNotification) => {
  if (conversationId == null) return;
  const key = popupKey(accountId, conversationId);
  const notifications = openPopups.get(key) || new Set();
  notifications.add(nativeNotification);
  openPopups.set(key, notifications);
  if ('onclose' in nativeNotification) {
    nativeNotification.onclose = () => {
      notifications.delete(nativeNotification);
      if (!notifications.size && openPopups.get(key) === notifications) {
        openPopups.delete(key);
      }
    };
  }
};

const forgetPopup = (accountId, conversationId, notification) => {
  const key = popupKey(accountId, conversationId);
  const notifications = openPopups.get(key);
  if (!notifications) return;
  notifications.delete(notification);
  if (!notifications.size) openPopups.delete(key);
};

const showPersistentPopup = async ({
  accountId,
  conversationId,
  title,
  body,
  icon,
  tag,
}) => {
  if (!('serviceWorker' in navigator)) {
    throw new Error('Service worker is unavailable for popup notifications');
  }

  let activeRegistration;
  let dismissed = false;
  const persistentPopup = {
    close: async () => {
      dismissed = true;
      if (!activeRegistration) return;
      try {
        const notifications = await activeRegistration.getNotifications({
          tag,
        });
        notifications.forEach(notification => notification.close());
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Could not close popup notification', error);
      }
    },
  };
  rememberPopup(accountId, conversationId, persistentPopup);

  try {
    const registration =
      (await navigator.serviceWorker.getRegistration('/sw.js')) ||
      (await navigator.serviceWorker.register('/sw.js', {
        updateViaCache: 'none',
      }));
    activeRegistration = registration.active
      ? registration
      : await navigator.serviceWorker.ready;
    if (dismissed) return;
    const url = conversationId
      ? frontendURL(conversationUrl({ accountId, id: conversationId }))
      : '/app';
    await activeRegistration.showNotification(title, {
      body,
      icon,
      tag,
      data: { url },
    });
    if (dismissed) await persistentPopup.close();
  } catch (error) {
    forgetPopup(accountId, conversationId, persistentPopup);
    throw error;
  }
};

export const closePopupNotification = (accountId, conversationId) => {
  if (conversationId == null) return;
  const key = popupKey(accountId, conversationId);
  const notifications = openPopups.get(key);
  if (!notifications) return;
  openPopups.delete(key);
  notifications.forEach(notification => notification.close());
};

export const showPopupNotification = async (payload, store) => {
  const notification = payload?.notification || payload;
  if (!notification?.notification_type) return;
  const accountId =
    notification.account_id || store?.getters?.getCurrentAccountId;
  if (
    !isPopupNotificationEnabled(
      notification.notification_type,
      store,
      accountId
    )
  ) {
    return;
  }
  if (typeof Notification === 'undefined') return;
  if (Notification.permission !== 'granted') return;

  const { conversationId, senderName, icon } =
    conversationFromNotification(notification);
  if (isViewingConversation(accountId, conversationId)) return;

  const title = senderName || notification.notification_type;
  const body = popupMessageBody(notification.push_message_body, senderName);

  const tag = `${notification.notification_type}_${conversationId}_${notification.id}`;
  try {
    const nativeNotification = new Notification(title, { tag, body, icon });
    rememberPopup(
      accountId,
      conversationId || notification.id,
      nativeNotification
    );

    nativeNotification.onclick = event => {
      event?.preventDefault?.();
      window.focus();
      nativeNotification.close();
      navigateToConversation(accountId, conversationId);
    };
  } catch (error) {
    // Mobile browsers commonly reject the page Notification constructor.
    await showPersistentPopup({
      accountId,
      conversationId,
      title,
      body,
      icon,
      tag,
    });
  }
};

export function usePopupNotifications() {
  return {
    showPopupNotification,
    closePopupNotification,
    requestPopupNotificationPermission,
  };
}
