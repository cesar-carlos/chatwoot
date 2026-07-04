export function isIosSafariWithoutPwa() {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') {
    return false;
  }

  const ua = navigator.userAgent || '';
  const isIOS = /iPad|iPhone|iPod/.test(ua);
  const isStandalone =
    window.matchMedia?.('(display-mode: standalone)')?.matches ||
    window.navigator.standalone === true;

  return isIOS && !isStandalone;
}

export function supportsOsNotifications() {
  return typeof Notification !== 'undefined';
}
