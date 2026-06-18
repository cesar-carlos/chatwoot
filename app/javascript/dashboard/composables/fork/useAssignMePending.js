// FORK: assignme - pending state for fast-assign concurrent request guard
import { ref, watch } from 'vue';

export function normalizeAssignConversationIds(
  conversationId,
  selectedConversationIds
) {
  if (conversationId) {
    return Array.isArray(conversationId) ? conversationId : [conversationId];
  }

  return selectedConversationIds;
}

export function useAssignMePending({ store } = {}) {
  const pendingAssignConversationIds = ref(new Map());

  function isAssignPending(conversationId) {
    return pendingAssignConversationIds.value.has(conversationId);
  }

  function markAssignPendingUntilResolved(conversationIds, assigneeId) {
    const nextPending = new Map(pendingAssignConversationIds.value);
    conversationIds.forEach(id => nextPending.set(id, assigneeId));
    pendingAssignConversationIds.value = nextPending;
  }

  function markAssignPending(conversationIds) {
    markAssignPendingUntilResolved(conversationIds, null);
  }

  function clearAssignPending(conversationIds) {
    const nextPending = new Map(pendingAssignConversationIds.value);
    conversationIds.forEach(id => nextPending.delete(id));
    pendingAssignConversationIds.value = nextPending;
  }

  function resolveAssignPending(conversationId, currentAssigneeId) {
    const expectedAssigneeId =
      pendingAssignConversationIds.value.get(conversationId);
    if (expectedAssigneeId === undefined) return;

    if (Number(currentAssigneeId) === Number(expectedAssigneeId)) {
      clearAssignPending([conversationId]);
    }
  }

  if (store) {
    watch(
      () => {
        const conversationList =
          store.state?.conversations?.allConversations || [];

        return Array.from(pendingAssignConversationIds.value.entries()).map(
          ([id, expectedAssigneeId]) => {
            const conversation = conversationList.find(item => item.id === id);

            return {
              id,
              expectedAssigneeId,
              currentAssigneeId: conversation?.meta?.assignee?.id,
            };
          }
        );
      },
      entries => {
        entries.forEach(({ id, expectedAssigneeId, currentAssigneeId }) => {
          if (
            pendingAssignConversationIds.value.has(id) &&
            Number(currentAssigneeId) === Number(expectedAssigneeId)
          ) {
            clearAssignPending([id]);
          }
        });
      },
      { deep: true }
    );
  }

  return {
    isAssignPending,
    markAssignPending,
    markAssignPendingUntilResolved,
    clearAssignPending,
    resolveAssignPending,
  };
}
