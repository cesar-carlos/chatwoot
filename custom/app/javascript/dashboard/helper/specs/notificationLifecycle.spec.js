import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const authCookie = vi.hoisted(() => vi.fn(() => 'session'));
vi.mock('js-cookie', () => ({ default: { get: authCookie } }));
import { requestAndSubscribe, cleanupPushOnLogout } from '../pushHelper';
import { startPushSession } from '../pushSession';
import { waitForActiveWorker } from '../serviceWorker';
import { logoutWithPushCleanup } from '../pushLogout';

describe('notification session lifecycle', () => {
  let registration;
  let subscription;
  let api;
  beforeEach(() => {
    startPushSession();
    authCookie.mockReturnValue('session');
    localStorage.clear();
    subscription = {
      endpoint: 'https://push.example.test/current',
      options: { applicationServerKey: new Uint8Array([1, 2, 3]) },
      getKey: () => new Uint8Array([4, 5, 6]),
      unsubscribe: vi.fn().mockResolvedValue(true),
    };
    registration = {
      active: { state: 'activated' },
      pushManager: {
        getSubscription: vi.fn().mockResolvedValue(subscription),
        subscribe: vi.fn().mockResolvedValue(subscription),
      },
    };
    api = {
      post: vi.fn().mockResolvedValue({}),
      delete: vi.fn().mockResolvedValue({}),
    };
    vi.stubGlobal('axios', api);
    window.matchMedia = vi.fn(() => ({ matches: false }));
    window.chatwootConfig = { vapidPublicKey: new Uint8Array([1, 2, 3]) };
    Object.defineProperty(window, 'isSecureContext', {
      configurable: true,
      value: true,
    });
    vi.stubGlobal('Notification', { permission: 'granted' });
    vi.stubGlobal('PushManager', class {});
    vi.stubGlobal('navigator', {
      userAgent: 'Chrome',
      platform: 'Linux',
      serviceWorker: {
        register: vi.fn().mockResolvedValue(registration),
        getRegistration: vi.fn().mockResolvedValue(registration),
      },
    });
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('waits for the exact registration to activate before subscribing', async () => {
    const worker = new EventTarget();
    worker.state = 'installing';
    const inactive = new EventTarget();
    inactive.installing = worker;
    inactive.pushManager = registration.pushManager;
    inactive.pushManager.getSubscription.mockResolvedValue(null);
    navigator.serviceWorker.register.mockResolvedValue(inactive);
    const pending = requestAndSubscribe();
    await vi.waitFor(() =>
      expect(navigator.serviceWorker.register).toHaveBeenCalled()
    );
    expect(registration.pushManager.subscribe).not.toHaveBeenCalled();
    worker.state = 'activated';
    inactive.active = worker;
    worker.dispatchEvent(new Event('statechange'));
    await expect(pending).resolves.toMatchObject({ status: 'subscribed' });
    expect(registration.pushManager.subscribe).toHaveBeenCalledOnce();
  });

  it('times out an inactive worker and releases its listeners', async () => {
    vi.useFakeTimers();
    const worker = new EventTarget();
    worker.state = 'installing';
    const inactive = new EventTarget();
    inactive.installing = worker;
    const pending = waitForActiveWorker(inactive);
    const assertion = expect(pending).rejects.toThrow('activation timed out');
    await vi.advanceTimersByTimeAsync(10000);
    await assertion;
  });

  it('aborts stalled synchronization and allows logout without waiting for that queue', async () => {
    let signal;
    api.post.mockImplementation(
      (url, body, options) =>
        new Promise((resolve, reject) => {
          signal = options.signal;
          signal.addEventListener('abort', () =>
            reject(new Error('cancelled'))
          );
        })
    );
    const sync = requestAndSubscribe().catch(error => error);
    await vi.waitFor(() => expect(api.post).toHaveBeenCalled());
    const clear = vi.fn();
    await logoutWithPushCleanup('/auth/sign_out', clear);
    expect(signal.aborted).toBe(true);
    expect(subscription.unsubscribe).toHaveBeenCalledOnce();
    expect(clear).toHaveBeenCalledOnce();
    expect((await sync).message).toBe('cancelled');
    expect(localStorage.getItem('chatwoot_push_enabled')).toBe('false');
  });

  it('rejects an ignored cancellation response without persisting late opt-in', async () => {
    let resolve;
    api.post.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const pending = requestAndSubscribe().catch(error => error);
    await vi.waitFor(() => expect(api.post).toHaveBeenCalled());
    await cleanupPushOnLogout();
    resolve({});
    expect((await pending).message).toContain('expired session');
    expect(localStorage.getItem('chatwoot_push_enabled')).toBe('false');
    expect(() => requestAndSubscribe()).toThrow('session is ending');
  });

  it('limits total logout cleanup to ten seconds and attempts local cleanup first', async () => {
    vi.useFakeTimers();
    api.delete.mockImplementation((url, options) => {
      if (url === '/auth/sign_out') return Promise.resolve({});
      return new Promise((resolve, reject) => {
        options.signal.addEventListener('abort', () =>
          reject(new Error('cancelled'))
        );
      });
    });
    const clear = vi.fn();
    const pending = logoutWithPushCleanup('/auth/sign_out', clear);
    const logger = vi.spyOn(console, 'error').mockImplementation(() => {});
    await vi.advanceTimersByTimeAsync(10000);
    await pending;
    expect(subscription.unsubscribe).toHaveBeenCalled();
    expect(clear).toHaveBeenCalled();
    expect(logger).toHaveBeenCalledWith(
      'Browser push cleanup failed during logout'
    );
  });

  it('bounds synchronization requests with timeout and abort', async () => {
    vi.useFakeTimers();
    let signal;
    api.post.mockImplementation(
      (url, body, options) =>
        new Promise((resolve, reject) => {
          signal = options.signal;
          signal.addEventListener('abort', () => reject(new Error('timeout')));
        })
    );
    const pending = requestAndSubscribe().catch(error => error);
    await vi.advanceTimersByTimeAsync(10001);
    expect(signal.aborted).toBe(true);
    expect((await pending).message).toBe('timeout');
  });
});
