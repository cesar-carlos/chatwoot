import store from 'dashboard/store';
import wootConstants from 'dashboard/constants/globals';

/** Reopen a resolved Wavoip thread as pending when an inbound call surfaces. */
export async function reopenWavoipInboundConversation(conversationId) {
  if (!conversationId) return;

  const lookup = store.getters.getConversationById;
  const conversation =
    typeof lookup === 'function' ? lookup(conversationId) : null;
  if (conversation?.status === wootConstants.STATUS_TYPE.PENDING) return;

  try {
    await store.dispatch('toggleStatus', {
      conversationId,
      status: wootConstants.STATUS_TYPE.PENDING,
    });
    // Default inbox filter is "open"; switch so the ringing thread is visible.
    store.dispatch('setChatStatusFilter', wootConstants.STATUS_TYPE.PENDING);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.debug('[Wavoip] reopen inbound conversation failed', error);
  }
}
