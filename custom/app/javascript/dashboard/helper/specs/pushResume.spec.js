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
});
