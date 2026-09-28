import { beforeEach, describe, expect, it, vi } from 'vitest';

const subscriptionApi = vi.hoisted(() => ({
  create: vi.fn(),
  destroyBrowserSubscription: vi.fn(),
}));

vi.mock('../../api/notificationSubscription', () => ({
  default: subscriptionApi,
}));

vi.mock('../../api/auth', () => ({
  default: { hasAuthCookie: () => true },
}));

import {
  ensurePushSubscription,
  getPushEnvironment,
  requestAndSubscribe,
  unsubscribePush,
} from '../pushHelper';

const applicationServerKey = new Uint8Array([1, 2, 3]);

const buildSubscription = (overrides = {}) => ({
  endpoint: 'https://push.example.test/device',
  options: { applicationServerKey: applicationServerKey.buffer },
  getKey: vi.fn(() => new Uint8Array([4, 5, 6]).buffer),
  unsubscribe: vi.fn().mockResolvedValue(true),
  ...overrides,
});

describe('pushHelper', () => {
  let pushManager;
  let subscription;

  beforeEach(() => {
    subscription = buildSubscription();
    pushManager = {
      getSubscription: vi.fn().mockResolvedValue(null),
      subscribe: vi.fn().mockResolvedValue(subscription),
    };

    vi.clearAllMocks();
    localStorage.clear();
    subscriptionApi.create.mockResolvedValue({});
    subscriptionApi.destroyBrowserSubscription.mockResolvedValue({});
    window.chatwootConfig = { vapidPublicKey: applicationServerKey };
    window.matchMedia = vi.fn().mockReturnValue({ matches: false });
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value: 'Mozilla/5.0 Chrome',
    });
    Object.defineProperty(navigator, 'platform', {
      configurable: true,
      value: 'Linux',
    });
    Object.defineProperty(navigator, 'maxTouchPoints', {
      configurable: true,
      value: 0,
    });
    Object.defineProperty(navigator, 'standalone', {
      configurable: true,
      value: false,
    });
    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        register: vi.fn().mockResolvedValue({ pushManager }),
      },
    });
    global.PushManager = class PushManager {};
    global.Notification = {
      permission: 'granted',
      requestPermission: vi.fn(),
    };
  });

  it('requires Home Screen installation on iOS outside standalone mode', () => {
    Object.defineProperty(navigator, 'userAgent', {
      configurable: true,
      value: 'Mozilla/5.0 (iPhone)',
    });

    expect(getPushEnvironment()).toEqual({
      supported: false,
      status: 'requires_install',
      permission: 'granted',
    });
  });

  it('does not subscribe when permission was granted only for open-panel alerts', async () => {
    const result = await ensurePushSubscription();

    expect(pushManager.subscribe).not.toHaveBeenCalled();
    expect(subscriptionApi.create).not.toHaveBeenCalled();
    expect(result.status).toBe('unsubscribed');
  });

  it('recreates a missing granted subscription and synchronizes it', async () => {
    localStorage.setItem('chatwoot_push_enabled', 'true');
    const result = await ensurePushSubscription();

    expect(pushManager.subscribe).toHaveBeenCalledWith({
      userVisibleOnly: true,
      applicationServerKey,
    });
    expect(subscriptionApi.create).toHaveBeenCalledWith(
      expect.objectContaining({
        subscription_type: 'browser_push',
        subscription_attributes: expect.objectContaining({
          endpoint: subscription.endpoint,
        }),
      })
    );
    expect(result.status).toBe('subscribed');
  });

  it('requests permission as a Promise only when explicitly called', async () => {
    global.Notification.permission = 'default';
    global.Notification.requestPermission.mockResolvedValue('granted');

    const result = await requestAndSubscribe();

    expect(global.Notification.requestPermission).toHaveBeenCalledOnce();
    expect(result.status).toBe('subscribed');
  });

  it('replaces a subscription created with a different VAPID key', async () => {
    const staleSubscription = buildSubscription({
      endpoint: 'https://push.example.test/stale',
      options: {
        applicationServerKey: new Uint8Array([9, 9, 9]).buffer,
      },
    });
    pushManager.getSubscription.mockResolvedValue(staleSubscription);

    const result = await ensurePushSubscription();

    expect(subscriptionApi.destroyBrowserSubscription).toHaveBeenCalledWith(
      staleSubscription.endpoint
    );
    expect(staleSubscription.unsubscribe).toHaveBeenCalled();
    expect(pushManager.subscribe).toHaveBeenCalled();
    expect(result.status).toBe('subscribed');
  });

  it('removes the local subscription even when backend removal fails', async () => {
    pushManager.getSubscription.mockResolvedValue(subscription);
    const serverError = new Error('backend unavailable');
    subscriptionApi.destroyBrowserSubscription.mockRejectedValue(serverError);

    const result = await unsubscribePush();

    expect(subscription.unsubscribe).toHaveBeenCalled();
    expect(result).toMatchObject({
      status: 'unsubscribed',
      serverError,
    });
  });

  it('does not recreate a subscription after an explicit opt-out', async () => {
    pushManager.getSubscription
      .mockResolvedValueOnce(subscription)
      .mockResolvedValue(null);

    await unsubscribePush();
    const result = await ensurePushSubscription();

    expect(localStorage.getItem('chatwoot_push_enabled')).toBe('false');
    expect(pushManager.subscribe).not.toHaveBeenCalled();
    expect(subscriptionApi.create).not.toHaveBeenCalled();
    expect(result.status).toBe('unsubscribed');
  });
});
