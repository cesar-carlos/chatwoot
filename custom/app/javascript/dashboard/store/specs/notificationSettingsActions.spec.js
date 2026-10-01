import { beforeEach, describe, expect, it, vi } from 'vitest';
import { notificationSettingsActions as actions } from '../notificationSettingsActions';
import { notificationReadMutations } from '../notificationReadActions';
import types from 'dashboard/store/mutation-types';

describe('account-scoped notification preferences', () => {
  let context;
  let api;
  beforeEach(() => {
    context = {
      state: { uiFlags: {} },
      rootGetters: { getCurrentAccountId: 1 },
      commit: vi.fn(),
    };
    api = { get: vi.fn(), patch: vi.fn() };
    vi.stubGlobal('axios', api);
  });
  it('rejects updates before a successful load', async () => {
    await expect(actions.update(context, {})).rejects.toThrow('not ready');
    expect(api.patch).not.toHaveBeenCalled();
  });
  it('propagates failed loads rather than representing empty preferences', async () => {
    api.get.mockRejectedValue(new Error('offline'));
    await expect(actions.get(context, 1)).rejects.toThrow('offline');
    expect(context.commit).toHaveBeenCalledWith(
      types.SET_USER_NOTIFICATION_UI_FLAG,
      expect.objectContaining({ loadError: true })
    );
    expect(context.commit).not.toHaveBeenCalledWith(
      types.SET_USER_NOTIFICATION,
      expect.anything()
    );
  });
  it('drops old responses after switching accounts', async () => {
    let finish;
    api.get
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      )
      .mockResolvedValueOnce({ data: { selected_push_flags: ['push_new'] } });
    const first = actions.get(context, 1);
    context.rootGetters.getCurrentAccountId = 2;
    await actions.get(context, 2);
    finish({ data: { selected_push_flags: ['push_old'] } });
    await first;
    expect(api.get).toHaveBeenNthCalledWith(
      1,
      '/api/v1/accounts/1/notification_settings'
    );
    expect(context.commit).toHaveBeenCalledWith(types.SET_USER_NOTIFICATION, {
      selected_push_flags: ['push_new'],
    });
    expect(context.commit).not.toHaveBeenCalledWith(
      types.SET_USER_NOTIFICATION,
      { selected_push_flags: ['push_old'] }
    );
  });
  it('preserves newer and other-account notifications in a bulk read receipt', () => {
    const state = {
      records: {
        1: { id: 1, account_id: 1 },
        2: { id: 2, account_id: 1 },
        3: { id: 3, account_id: 2 },
      },
    };
    notificationReadMutations.applyReadReceipt(state, {
      account_id: 1,
      through_notification_id: 1,
      read_at: 'now',
    });
    expect(state.records[1].read_at).toBe('now');
    expect(state.records[2].read_at).toBeUndefined();
    expect(state.records[3].read_at).toBeUndefined();
  });
});
