import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const ensurePushSubscription = vi.hoisted(() => vi.fn());
const getPushEnvironment = vi.hoisted(() => vi.fn());
const authCookie = vi.hoisted(() => vi.fn());

vi.mock('customDashboard/helper/pushHelper', () => ({
  ensurePushSubscription,
  getPushEnvironment,
}));
vi.mock('js-cookie', () => ({ default: { get: authCookie } }));

import {
  BROWSER_PUSH_SYNC_EVENT,
  startBrowserPushResumeSync,
  stopBrowserPushResumeSync,
  syncBrowserPush,
} from 'customDashboard/helper/pushResume';
import {
  beginPushLogout,
  startPushSession,
} from 'customDashboard/helper/pushSession';

describe('browser push resume synchronization', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authCookie.mockReturnValue('authenticated');
    ensurePushSubscription.mockResolvedValue({
      status: 'subscribed',
      permission: 'granted',
    });
    getPushEnvironment.mockReturnValue({ permission: 'denied' });
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: false,
    });
  });

  afterEach(() => stopBrowserPushResumeSync());

  it('revalidates on return and publishes the current subscription state', async () => {
    const listener = vi.fn();
    window.addEventListener(BROWSER_PUSH_SYNC_EVENT, listener, { once: true });
    startBrowserPushResumeSync();

    document.dispatchEvent(new Event('visibilitychange'));

    await vi.waitFor(() => expect(listener).toHaveBeenCalledOnce());
    expect(ensurePushSubscription).toHaveBeenCalledOnce();
    expect(listener.mock.calls[0][0].detail).toEqual({
      status: 'subscribed',
      permission: 'granted',
      cleanupError: false,
      endpoint: undefined,
    });
  });

  it('does not sync while hidden or after authentication ends', () => {
    startBrowserPushResumeSync();
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: true,
    });
    document.dispatchEvent(new Event('visibilitychange'));
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: false,
    });
    authCookie.mockReturnValue(undefined);
    document.dispatchEvent(new Event('visibilitychange'));

    expect(ensurePushSubscription).not.toHaveBeenCalled();
  });

  it('coalesces focus and visibility events and recovers a blocked permission', async () => {
    let finish;
    ensurePushSubscription.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    getPushEnvironment.mockReturnValue({ permission: 'denied' });
    startBrowserPushResumeSync();
    getPushEnvironment.mockReturnValue({ permission: 'granted' });
    window.dispatchEvent(new Event('focus'));
    document.dispatchEvent(new Event('visibilitychange'));
    expect(ensurePushSubscription).toHaveBeenCalledOnce();
    expect(ensurePushSubscription).toHaveBeenCalledWith({
      recoverPermission: true,
    });
    finish({ status: 'subscribed', permission: 'granted' });
    await syncBrowserPush();
  });

  it('does not automatically opt in when Pop-up permission is granted', async () => {
    getPushEnvironment.mockReturnValue({ permission: 'default' });
    startBrowserPushResumeSync();
    getPushEnvironment.mockReturnValue({ permission: 'granted' });
    await syncBrowserPush();
    expect(ensurePushSubscription).toHaveBeenCalledWith({
      recoverPermission: false,
    });
  });

  it('publishes an error state without exposing endpoint details', async () => {
    const listener = vi.fn();
    const logger = vi.spyOn(console, 'error').mockImplementation(() => {});
    ensurePushSubscription.mockRejectedValue(new Error('private endpoint'));
    window.addEventListener(BROWSER_PUSH_SYNC_EVENT, listener, { once: true });

    await syncBrowserPush();

    expect(listener.mock.calls[0][0].detail).toEqual({
      status: 'error',
      permission: 'denied',
    });
    expect(logger).toHaveBeenCalledWith(
      'Push subscription synchronization failed'
    );
    logger.mockRestore();
  });

  it('ignores old sync results even after a new session begins', async () => {
    startPushSession();
    let finish;
    ensurePushSubscription.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const listener = vi.fn();
    window.addEventListener(BROWSER_PUSH_SYNC_EVENT, listener);
    const pending = syncBrowserPush();
    beginPushLogout();
    startPushSession();
    finish({ status: 'subscribed', permission: 'granted' });
    await pending;
    expect(listener).not.toHaveBeenCalled();
    window.removeEventListener(BROWSER_PUSH_SYNC_EVENT, listener);
  });
});
