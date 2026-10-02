import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { waitForActiveWorker } from 'customDashboard/helper/serviceWorker';

const DEFAULT_ICON = '/brand-assets/logo_thumbnail.svg';
const SKIPPED_POPUP_TYPES = new Set(['voice_call_incoming']);
export const POPUP_FLAGS_BY_ACCOUNT_KEY = 'popup_notification_flags_by_account';
export const POPUP_DELIVERY_ERROR_EVENT = 'chatwoot:popup-delivery-error';
const LEGACY_POPUP_FLAGS_KEY = 'popup_notification_flags';

const openPopups = new Map();
const popupContexts = new Map();
let currentRoute = () => null;
export const setPopupRouteResolver = resolver => {
  currentRoute = resolver;
};
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

export const isViewingConversation = (
  accountId,
  conversationId,
  route = currentRoute()
) => {
  if (document.visibilityState !== 'visible') return false;
  if (conversationId == null || conversationId === '') return false;
  if (route?.params) {
    const params = route.params;
    const routedConversation =
      params.conversation_id ??
      params.conversationId ??
      (route.name === 'inbox_view_conversation' &&
      params.type === 'conversation'
        ? params.id
        : '');
    return (
      String(params.accountId) === String(accountId) &&
      String(routedConversation) === String(conversationId)
    );
  }
  const path = window.location.pathname || '';
  const match = path.match(
    /^\/app\/accounts\/(\d+)\/(?:.*\/)?conversations\/(\d+)(?:\/|$)/
  );
  const inboxView = path.match(
    /^\/app\/accounts\/(\d+)\/inbox-view\/conversation\/(\d+)(?:\/|$)/
  );
  const normalized = match || inboxView;
  return (
    normalized?.[1] === String(accountId) &&
    normalized?.[2] === String(conversationId)
  );
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

const navigateToConversation = async (accountId, conversationId) => {
  if (!accountId || !conversationId) return;
  const path = frontendURL(conversationUrl({ accountId, id: conversationId }));
  const { router } = await import('dashboard/routes');
  await router.push({ path });
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
        popupContexts.delete(key);
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
  notificationId,
  userId,
  actionLabels,
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
        console.error('Could not close popup notification');
      }
    },
  };
  rememberPopup(accountId, notificationId, persistentPopup);

  try {
    const registration =
      (await navigator.serviceWorker.getRegistration('/sw.js')) ||
      (await navigator.serviceWorker.register('/sw.js', {
        updateViaCache: 'none',
      }));
    activeRegistration = await waitForActiveWorker(registration);
    if (dismissed) return;
    const url = conversationId
      ? frontendURL(conversationUrl({ accountId, id: conversationId }))
      : '/app';
    await activeRegistration.showNotification(title, {
      body,
      icon,
      tag,
      actions:
        userId && notificationId
          ? [
              {
                action: 'open_conversation',
                title: actionLabels?.open || 'Open conversation',
              },
              {
                action: 'mark_read',
                title: actionLabels?.read || 'Mark as read',
              },
            ].slice(0, Notification.maxActions ?? 0)
          : [],
      data: {
        url,
        account_id: accountId,
        notification_id: notificationId,
        user_id: userId,
        conversation_id: conversationId,
      },
    });
    if (dismissed) await persistentPopup.close();
  } catch (error) {
    forgetPopup(accountId, notificationId, persistentPopup);
    throw error;
  }
};

async function closePersistentNotifications(matches, receipt) {
  try {
    const registration =
      await navigator.serviceWorker?.getRegistration('/sw.js');
    registration?.active?.postMessage?.({
      type: 'notifications-read',
      receipt,
    });
    const notifications = await registration?.getNotifications();
    notifications
      ?.filter(notification => matches(notification.data || {}))
      .forEach(notification => notification.close());
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Could not close persistent notifications');
  }
}

export const closePopupNotification = (accountId, notificationId) => {
  if (notificationId == null) return;
  const key = popupKey(accountId, notificationId);
  const notifications = openPopups.get(key);
  openPopups.delete(key);
  popupContexts.delete(key);
  notifications?.forEach(notification => notification.close());
  closePersistentNotifications(
    data =>
      String(data.account_id) === String(accountId) &&
      String(data.notification_id) === String(notificationId),
    { account_id: accountId, notification_id: notificationId }
  );
};

export const closeReadPopupNotifications = receipt => {
  const matches = data =>
    String(data.account_id) === String(receipt.account_id) &&
    (!receipt.user_id || String(data.user_id) === String(receipt.user_id)) &&
    Number(data.notification_id) <= Number(receipt.through_notification_id) &&
    (!receipt.conversation_display_id ||
      String(data.conversation_id) === String(receipt.conversation_display_id));
  popupContexts.forEach((data, key) => {
    if (matches(data)) {
      openPopups.get(key)?.forEach(notification => notification.close());
      openPopups.delete(key);
      popupContexts.delete(key);
    }
  });
  closePersistentNotifications(matches, receipt);
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

  const title =
    notification.notification_title ||
    senderName ||
    notification.notification_type;
  const body = popupMessageBody(
    notification.push_message_body,
    title === senderName ? senderName : null
  );

  const tag = `${notification.notification_type}_${conversationId}_${notification.id}`;
  const userId =
    notification.user_id ||
    notification.user?.id ||
    store?.getters?.getCurrentUser?.id;
  popupContexts.set(popupKey(accountId, notification.id), {
    account_id: accountId,
    notification_id: notification.id,
    conversation_id: conversationId,
    user_id: userId,
  });
  const persistentOptions = {
    accountId,
    conversationId,
    notificationId: notification.id,
    userId,
    actionLabels: notification.action_labels,
    title,
    body,
    icon,
    tag,
  };
  // Actions are available only on persistent notifications, including desktop.
  if (
    userId &&
    notification.id &&
    Notification.maxActions > 0 &&
    'serviceWorker' in navigator
  ) {
    await showPersistentPopup(persistentOptions);
    return;
  }
  try {
    const nativeNotification = new Notification(title, { tag, body, icon });
    rememberPopup(accountId, notification.id, nativeNotification);

    nativeNotification.onerror = () => {
      nativeNotification.close();
      // eslint-disable-next-line no-console
      console.error('Desktop notification delivery failed');
      window.dispatchEvent(new CustomEvent(POPUP_DELIVERY_ERROR_EVENT));
    };
    nativeNotification.onclick = async event => {
      event?.preventDefault?.();
      nativeNotification.close();
      try {
        window.focus();
        await navigateToConversation(accountId, conversationId);
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error('Could not navigate from desktop notification');
        try {
          window.location.assign(
            frontendURL(conversationUrl({ accountId, id: conversationId }))
          );
        } catch (navigationError) {
          window.dispatchEvent(new CustomEvent(POPUP_DELIVERY_ERROR_EVENT));
        }
      }
    };
  } catch (error) {
    // Mobile browsers commonly reject the page Notification constructor.
    await showPersistentPopup(persistentOptions);
  }
};

export function usePopupNotifications() {
  return {
    showPopupNotification,
    closePopupNotification,
    requestPopupNotificationPermission,
  };
}
