import NotificationsAPI from 'dashboard/api/notifications';
import types from 'dashboard/store/mutation-types';
import { closeReadPopupNotifications } from 'customDashboard/composables/usePopupNotifications';

export const notificationReadMutations = {
  applyReadReceipt(state, receipt) {
    Object.values(state.records).forEach(notification => {
      if (
        String(notification.account_id) === String(receipt.account_id) &&
        notification.id <= receipt.through_notification_id &&
        (!receipt.conversation_display_id ||
          String(notification.primary_actor?.id) ===
            String(receipt.conversation_display_id))
      ) {
        notification.read_at = receipt.read_at;
      }
    });
  },
};
const read = async ({ commit, dispatch }, request) => {
  commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: true });
  try {
    const { data } = await request();
    await dispatch('applyReadReceipt', data);
  } finally {
    commit(types.SET_NOTIFICATIONS_UI_FLAG, { isUpdating: false });
  }
};
export const notificationReadActions = {
  async applyReadReceipt({ commit, dispatch, rootGetters }, receipt) {
    if (
      receipt.user_id &&
      String(rootGetters.getCurrentUser?.id) !== String(receipt.user_id)
    )
      return;
    closeReadPopupNotifications(receipt);
    if (String(rootGetters.getCurrentAccountId) !== String(receipt.account_id))
      return;
    commit('applyReadReceipt', receipt);
    await dispatch('unReadCount');
  },
  async read(context, { primaryActorType, primaryActorId }) {
    return read(context, () =>
      NotificationsAPI.read(primaryActorType, primaryActorId)
    );
  },
  readAll(context) {
    return read(context, () => NotificationsAPI.readAll());
  },
};
