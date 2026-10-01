import { beforeEach, describe, expect, it, vi } from 'vitest';

const subscriptionApi = vi.hoisted(() => ({ create: vi.fn() }));
const destroyBrowserSubscription = vi.hoisted(() => vi.fn());
const authCookie = vi.hoisted(() => vi.fn(() => 'authenticated'));

vi.mock('dashboard/api/notificationSubscription', () => ({
  default: subscriptionApi,
}));

vi.mock('customDashboard/api/notificationSubscription', () => ({
  destroyBrowserSubscription,
  synchronizeBrowserSubscription: subscriptionApi.create,
}));

vi.mock('js-cookie', () => ({
  default: { get: authCookie },
}));

import {
  ensurePushSubscription,
  getPushEnvironment,
  requestAndSubscribe,
  unsubscribePush,
} from 'customDashboard/helper/pushHelper';

const applicationServerKey = new Uint8Array([1, 2, 3]);

const buildSubscription = (overrides = {}) => ({
  endpoint: 'https://push.example.test/device',
  options: { applicationServerKey: applicationServerKey.buffer },
  getKey: vi.fn(() => new Uint8Array([4, 5, 6]).buffer),
  unsubscribe: vi.fn().mockResolvedValue(true),
  ...overrides,
});

describe('custom browser push helper', () => {
  let pushManager;
  let subscription;

  beforeEach(() => {
    subscription = buildSubscription();
    pushManager = {
      getSubscription: vi.fn().mockResolvedValue(null),
      subscribe: vi.fn().mockResolvedValue(subscription),
    };

    vi.clearAllMocks();
    authCookie.mockReturnValue('authenticated');
    localStorage.clear();
    subscriptionApi.create.mockResolvedValue({});
    destroyBrowserSubscription.mockResolvedValue({});
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
        register: vi
          .fn()
          .mockResolvedValue({ active: { state: 'activated' }, pushManager }),
        getRegistration: vi.fn().mockResolvedValue({ pushManager }),
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

  it('does not subscribe from a permission granted only for open-panel alerts', async () => {
    const result = await ensurePushSubscription();

    expect(pushManager.subscribe).not.toHaveBeenCalled();
    expect(subscriptionApi.create).not.toHaveBeenCalled();
    expect(result.status).toBe('unsubscribed');
  });

  it('recreates and synchronizes a missing opted-in subscription', async () => {
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

  it('requests permission only during explicit opt-in', async () => {
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

    expect(destroyBrowserSubscription).toHaveBeenCalledWith(
      staleSubscription.endpoint,
      expect.objectContaining({
        timeout: 10000,
        signal: expect.any(AbortSignal),
      })
    );
    expect(staleSubscription.unsubscribe).toHaveBeenCalledOnce();
    expect(pushManager.subscribe).toHaveBeenCalledOnce();
    expect(result.status).toBe('subscribed');
  });

  it('continues VAPID rotation when remote stale cleanup fails', async () => {
    const staleSubscription = buildSubscription({
      options: {
        applicationServerKey: new Uint8Array([9, 9, 9]).buffer,
      },
    });
    const cleanupError = new Error('backend unavailable');
    pushManager.getSubscription.mockResolvedValue(staleSubscription);
    destroyBrowserSubscription.mockRejectedValue(cleanupError);

    const result = await ensurePushSubscription();

    expect(staleSubscription.unsubscribe).toHaveBeenCalledOnce();
    expect(pushManager.subscribe).toHaveBeenCalledOnce();
    expect(result).toMatchObject({ status: 'subscribed', cleanupError });
  });

  it('removes the local subscription even when backend removal fails', async () => {
    pushManager.getSubscription.mockResolvedValue(subscription);
    const serverError = new Error('backend unavailable');
    destroyBrowserSubscription.mockRejectedValue(serverError);

    const result = await unsubscribePush();

    expect(subscription.unsubscribe).toHaveBeenCalledOnce();
    expect(result).toMatchObject({ status: 'unsubscribed', serverError });
    expect(navigator.serviceWorker.register).not.toHaveBeenCalled();
  });

  it('does not recreate a subscription after explicit opt-out', async () => {
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

  it('registers the service worker without using an HTTP cache', async () => {
    localStorage.setItem('chatwoot_push_enabled', 'true');

    await ensurePushSubscription();

    expect(navigator.serviceWorker.register).toHaveBeenCalledWith('/sw.js', {
      updateViaCache: 'none',
    });
  });

  it('serializes simultaneous subscription operations', async () => {
    localStorage.setItem('chatwoot_push_enabled', 'true');
    let releaseSubscription;
    pushManager.subscribe.mockReturnValue(
      new Promise(resolve => {
        releaseSubscription = () => resolve(subscription);
      })
    );

    const first = ensurePushSubscription();
    const second = ensurePushSubscription();
    await vi.waitFor(() => expect(releaseSubscription).toBeTypeOf('function'));

    expect(navigator.serviceWorker.register).toHaveBeenCalledTimes(1);
    releaseSubscription();
    await Promise.all([first, second]);
    expect(navigator.serviceWorker.register).toHaveBeenCalledTimes(2);
  });
});
