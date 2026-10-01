import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const unsubscribePush = vi.hoisted(() => vi.fn());
const clearCookiesOnLogout = vi.hoisted(() => vi.fn());

vi.mock('customDashboard/helper/pushHelper', () => ({
  cleanupPushOnLogout: unsubscribePush,
}));
vi.mock('dashboard/store/utils/api', () => ({ clearCookiesOnLogout }));

import Auth from 'dashboard/api/auth';

describe('browser push cleanup on logout', () => {
  let deleteSession;

  beforeEach(() => {
    vi.clearAllMocks();
    deleteSession = vi.fn().mockResolvedValue({ status: 200 });
    vi.stubGlobal('axios', { delete: deleteSession });
    unsubscribePush.mockResolvedValue({ status: 'unsubscribed' });
    clearCookiesOnLogout.mockResolvedValue();
  });

  afterEach(() => vi.unstubAllGlobals());

  it('unsubscribes the device before ending the authenticated session', async () => {
    await Auth.logout();

    expect(unsubscribePush).toHaveBeenCalledOnce();
    expect(deleteSession).toHaveBeenCalledWith('auth/sign_out');
    expect(unsubscribePush.mock.invocationCallOrder[0]).toBeLessThan(
      deleteSession.mock.invocationCallOrder[0]
    );
    expect(clearCookiesOnLogout).toHaveBeenCalledOnce();
  });

  it('still signs out when service worker cleanup fails', async () => {
    const logger = vi.spyOn(console, 'error').mockImplementation(() => {});
    unsubscribePush.mockRejectedValue(new Error('private endpoint'));

    await Auth.logout();

    expect(deleteSession).toHaveBeenCalledOnce();
    expect(logger).toHaveBeenCalledWith(
      'Browser push cleanup failed during logout'
    );
    logger.mockRestore();
  });
});
