import axios from 'axios';
import { actions } from '../../userNotificationSettings';
import * as types from '../../../mutation-types';

const commit = vi.fn();
// FORK: preferences require an account-scoped successful load before saving.
const context = () => ({
  commit,
  rootGetters: { getCurrentAccountId: 1 },
  state: { uiFlags: { loadedAccountId: '1' } },
});
global.axios = axios;
vi.mock('axios');

describe('#actions', () => {
  describe('#get', () => {
    it('sends correct actions if API is success', async () => {
      axios.get.mockResolvedValue({
        data: { selected_email_flags: ['conversation_creation'] },
      });
      await actions.get(context());
      expect(commit.mock.calls).toEqual([
        [
          types.default.SET_USER_NOTIFICATION_UI_FLAG,
          { isFetching: true, loadError: false, loadedAccountId: null },
        ],
        [
          types.default.SET_USER_NOTIFICATION,
          { selected_email_flags: ['conversation_creation'] },
        ],
        [
          types.default.SET_USER_NOTIFICATION_UI_FLAG,
          { isFetching: false, loadedAccountId: '1' },
        ],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.get.mockRejectedValue({ message: 'Incorrect header' });
      await expect(actions.get(context())).rejects.toEqual({
        message: 'Incorrect header',
      });
      expect(commit.mock.calls).toEqual([
        [
          types.default.SET_USER_NOTIFICATION_UI_FLAG,
          { isFetching: true, loadError: false, loadedAccountId: null },
        ],
        [
          types.default.SET_USER_NOTIFICATION_UI_FLAG,
          { isFetching: false, loadError: true },
        ],
      ]);
    });
  });

  describe('#update', () => {
    it('sends correct actions if API is success', async () => {
      axios.patch.mockResolvedValue({
        data: { selected_email_flags: ['conversation_creation'] },
      });
      await actions.update(context(), {
        selectedEmailFlags: ['conversation_creation'],
        selectedPushFlags: [],
      });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_USER_NOTIFICATION_UI_FLAG, { isUpdating: true }],
        [
          types.default.SET_USER_NOTIFICATION,
          { selected_email_flags: ['conversation_creation'] },
        ],
        [types.default.SET_USER_NOTIFICATION_UI_FLAG, { isUpdating: false }],
      ]);
    });
    it('sends correct actions if API is error', async () => {
      axios.patch.mockRejectedValue({ message: 'Incorrect header' });
      await expect(
        actions.update(context(), {
          selectedEmailFlags: ['conversation_creation'],
          selectedPushFlags: [],
        })
      ).rejects.toEqual({
        message: 'Incorrect header',
      });
      expect(commit.mock.calls).toEqual([
        [types.default.SET_USER_NOTIFICATION_UI_FLAG, { isUpdating: true }],
        [types.default.SET_USER_NOTIFICATION_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });
});
