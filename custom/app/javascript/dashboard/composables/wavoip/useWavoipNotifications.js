import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';

const DEFAULT_ICON = '/brand-assets/logo_thumbnail.svg';

export function notifyIncomingWavoipOffer(offer, inbox) {
  if (typeof Notification === 'undefined') return;
  if (Notification.permission !== 'granted') return;
  if (document.visibilityState === 'visible') return;

  const enabled =
    inbox?.provider_config?.offer_notification_enabled !== false &&
    inbox?.offer_notification_enabled !== false;
  if (!enabled) return;

  const peer = offer?.peer || {};
  const icon =
    inbox?.provider_config?.offer_notification_icon ||
    inbox?.offer_notification_icon ||
    DEFAULT_ICON;

  // eslint-disable-next-line no-new -- browser Notification API requires constructor side effect
  new Notification(peer.displayName || peer.phone || 'Incoming call', {
    tag: `chatwoot-wavoip-offer-${offer.id}`,
    body: peer.phone || '',
    icon,
  });
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
