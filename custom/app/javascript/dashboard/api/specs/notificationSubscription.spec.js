import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('dashboard/api/notificationSubscription', () => ({
  default: { url: '/api/v1/notification_subscriptions' },
}));

import { destroyBrowserSubscription } from 'customDashboard/api/notificationSubscription';

describe('browser push subscription API', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('limits endpoint removal so logout can continue on a stalled network', async () => {
    const deleteRequest = vi.fn().mockResolvedValue({});
    vi.stubGlobal('axios', { delete: deleteRequest });

    await destroyBrowserSubscription('https://push.example.test/device');

    expect(deleteRequest).toHaveBeenCalledWith(
      '/api/v1/notification_subscriptions',
      {
        params: { endpoint: 'https://push.example.test/device' },
        timeout: 10000,
      }
    );
  });
});
