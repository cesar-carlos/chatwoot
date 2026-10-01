import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { reactive, ref, nextTick } from 'vue';
const alert = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alert }));
import {
  executeNotificationRead,
  startNotificationActions,
} from '../notificationActions';

describe('recipient-validated notification actions', () => {
  let store;
  let router;
  let api;
  let stop;
  let message;
  const intent = { user_id: 7, account_id: 1, notification_id: 9 };
  beforeEach(() => {
    vi.clearAllMocks();
    store = {
      getters: reactive({
        getCurrentUser: { id: 7 },
        getCurrentAccountId: 1,
        getAuthUIFlags: { isFetching: false },
      }),
      dispatch: vi.fn().mockResolvedValue(),
    };
    router = {
      currentRoute: ref({
        params: { accountId: '1' },
        query: { notification_intent: 'nonce' },
      }),
      replace: vi.fn(async ({ query }) => {
        router.currentRoute.value.query = query;
      }),
      push: vi.fn().mockResolvedValue(),
    };
    api = {
      post: vi
        .fn()
        .mockResolvedValue({ data: { id: 9, account_id: 1, read_at: 'now' } }),
    };
    vi.stubGlobal('axios', api);
    vi.stubGlobal(
      'MessageChannel',
      class {
        constructor() {
          this.port1 = { close: vi.fn(), onmessage: null };
          this.port2 = { postMessage: data => this.port1.onmessage({ data }) };
        }
      }
    );
    message = vi.fn((data, ports) => {
      if (data.type === 'consume-notification-intent')
        ports[0].postMessage(intent);
    });
    vi.stubGlobal('navigator', {
      serviceWorker: {
        getRegistration: vi.fn().mockResolvedValue({
          active: { postMessage: message },
          getNotifications: vi.fn().mockResolvedValue([]),
        }),
      },
    });
  });
  afterEach(() => {
    stop?.();
    stop = null;
    vi.unstubAllGlobals();
  });

  it('does not execute for another recipient or an unauthenticated session', async () => {
    await expect(
      executeNotificationRead({ ...intent, user_id: 8 }, store)
    ).rejects.toThrow('recipient');
    store.getters.getCurrentUser = {};
    await expect(executeNotificationRead(intent, store)).rejects.toThrow(
      'recipient'
    );
    expect(api.post).not.toHaveBeenCalled();
  });
  it('waits for session loading and applies only successful reads', async () => {
    store.getters.getAuthUIFlags.isFetching = true;
    stop = startNotificationActions(router, store, key => key);
    await nextTick();
    expect(api.post).not.toHaveBeenCalled();
    store.getters.getAuthUIFlags.isFetching = false;
    await vi.waitFor(() => expect(api.post).toHaveBeenCalled());
    expect(api.post).toHaveBeenCalledWith(
      '/api/v1/accounts/1/notification_actions/9/read',
      {},
      { timeout: 10000 }
    );
    expect(store.dispatch).toHaveBeenCalledWith('notifications/unReadCount');
    expect(store.dispatch).toHaveBeenCalledWith('notifications/index');
  });
  it('consumes unauthenticated intents and never auto-marks after login', async () => {
    store.getters.getCurrentUser = {};
    stop = startNotificationActions(router, store, key => key);
    await vi.waitFor(() =>
      expect(router.push).toHaveBeenCalledWith({ name: 'login' })
    );
    store.getters.getCurrentUser = { id: 7 };
    await nextTick();
    expect(api.post).not.toHaveBeenCalled();
    expect(router.currentRoute.value.query.notification_intent).toBeUndefined();
  });
  it('shows delivery failures and makes no optimistic changes', async () => {
    api.post.mockRejectedValue(new Error('permission revoked'));
    stop = startNotificationActions(router, store, key => key);
    await vi.waitFor(() =>
      expect(alert).toHaveBeenCalledWith(
        'PROFILE_SETTINGS.FORM.NOTIFICATIONS.ACTION_READ_ERROR'
      )
    );
    expect(store.dispatch).not.toHaveBeenCalled();
  });
  it('rejects untrusted or expired URL intents', async () => {
    message.mockImplementation((data, [port]) => port.postMessage(null));
    stop = startNotificationActions(router, store, key => key);
    await vi.waitFor(() => expect(alert).toHaveBeenCalled());
    expect(api.post).not.toHaveBeenCalled();
  });
});
