/* global axios */
import types from 'dashboard/store/mutation-types';

let requestId = 0;
const flags = (commit, data) =>
  commit(types.SET_USER_NOTIFICATION_UI_FLAG, data);
const settingsUrl = accountId =>
  `/api/v1/accounts/${accountId}/notification_settings`;

export const notificationSettingsActions = {
  async get(
    { commit, rootGetters },
    accountId = rootGetters.getCurrentAccountId
  ) {
    requestId += 1;
    const id = requestId;
    flags(commit, {
      isFetching: true,
      loadError: false,
      loadedAccountId: null,
    });
    try {
      const response = await axios.get(settingsUrl(accountId));
      if (
        id !== requestId ||
        String(rootGetters.getCurrentAccountId) !== String(accountId)
      )
        return undefined;
      commit(types.SET_USER_NOTIFICATION, response.data);
      flags(commit, { isFetching: false, loadedAccountId: String(accountId) });
      return response.data;
    } catch (error) {
      if (id === requestId)
        flags(commit, { isFetching: false, loadError: true });
      throw error;
    }
  },
  async update(
    { commit, state, rootGetters },
    {
      selectedEmailFlags,
      selectedPushFlags,
      accountId = rootGetters.getCurrentAccountId,
    }
  ) {
    if (
      state.uiFlags.loadedAccountId !== String(accountId) ||
      state.uiFlags.isFetching ||
      state.uiFlags.isUpdating
    ) {
      throw new Error('Notification preferences are not ready for editing');
    }
    const id = requestId;
    flags(commit, { isUpdating: true });
    try {
      const response = await axios.patch(settingsUrl(accountId), {
        notification_settings: {
          selected_email_flags: selectedEmailFlags,
          selected_push_flags: selectedPushFlags,
        },
      });
      if (
        id === requestId &&
        String(rootGetters.getCurrentAccountId) === String(accountId)
      ) {
        commit(types.SET_USER_NOTIFICATION, response.data);
      }
      return response.data;
    } finally {
      flags(commit, { isUpdating: false });
    }
  },
};
