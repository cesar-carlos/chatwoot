import i18n from 'dashboard/i18n';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';

const DEFAULT_ICON = '/brand-assets/logo_thumbnail.svg';
// Page-context Notification instances — getNotifications() is SW-only.
const openOfferNotifications = new Map();

const offerNotificationTag = offerId => `chatwoot-wavoip-offer-${offerId}`;

export function closeIncomingWavoipOfferNotification(offerId) {
  if (!offerId) return;

  const notification = openOfferNotifications.get(offerId);
  if (!notification) return;

  openOfferNotifications.delete(offerId);
  notification.close();
}

export function notifyIncomingWavoipOffer(offer, inbox) {
  if (typeof Notification === 'undefined') return;
  if (Notification.permission !== 'granted') return;
  if (document.visibilityState === 'visible') return;
  if (!offer?.id) return;

  const enabled =
    inbox?.provider_config?.offer_notification_enabled !== false &&
    inbox?.offer_notification_enabled !== false;
  if (!enabled) return;

  const peer = offer?.peer || {};
  const icon =
    inbox?.provider_config?.offer_notification_icon ||
    inbox?.offer_notification_icon ||
    DEFAULT_ICON;

  const incomingCallTitle = i18n.global.t(
    'CONVERSATION.VOICE_CALL.INCOMING_CALL'
  );

  closeIncomingWavoipOfferNotification(offer.id);

  const notification = new Notification(
    peer.displayName || peer.phone || incomingCallTitle,
    {
      tag: offerNotificationTag(offer.id),
      body: peer.phone || '',
      icon,
    }
  );
  openOfferNotifications.set(offer.id, notification);
  notification.onclick = event => {
    event?.preventDefault?.();
    window.focus();
    notification.close();
  };
  notification.onclose = () => {
    if (openOfferNotifications.get(offer.id) === notification) {
      openOfferNotifications.delete(offer.id);
    }
  };
}

export function requestWavoipNotificationPermission() {
  if (typeof Notification === 'undefined')
    return Promise.resolve('unsupported');
  if (Notification.permission === 'granted') return Promise.resolve('granted');
  if (Notification.permission === 'denied') return Promise.resolve('denied');
  return Notification.requestPermission();
}

export function useWavoipNotifications() {
  const onOffer = (offer, inbox) => {
    notifyIncomingWavoipOffer(offer, inbox);
  };

  return {
    requestPermission: requestWavoipNotificationPermission,
    onOffer,
    notifyIncomingWavoipOffer,
  };
}

export function isWavoipInboxRestricted(inboxId) {
  return getWavoipDeviceStatus(inboxId).isRestricted.value;
}
