import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('dashboard/i18n', () => ({
  default: {
    global: {
      t: key => key,
    },
  },
}));

vi.mock('customDashboard/lib/wavoip/wavoipDeviceStatus', () => ({
  getWavoipDeviceStatus: () => ({ isRestricted: { value: false } }),
}));

import {
  closeIncomingWavoipOfferNotification,
  notifyIncomingWavoipOffer,
} from '../useWavoipNotifications';

describe('useWavoipNotifications', () => {
  let closeMock;

  beforeEach(() => {
    closeMock = vi.fn();
    global.Notification = vi.fn(function NotificationMock() {
      this.close = closeMock;
      this.onclose = null;
    });
    global.Notification.permission = 'granted';
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      get: () => 'hidden',
    });
  });

  it('closes a previously opened offer notification', () => {
    notifyIncomingWavoipOffer(
      { id: 'offer_1', peer: { displayName: 'Alice', phone: '+5511' } },
      { provider_config: {} }
    );

    expect(global.Notification).toHaveBeenCalled();

    closeIncomingWavoipOfferNotification('offer_1');

    expect(closeMock).toHaveBeenCalled();
  });

  it('is a no-op when no notification was opened for the offer', () => {
    expect(() =>
      closeIncomingWavoipOfferNotification('missing_offer')
    ).not.toThrow();
  });
});
