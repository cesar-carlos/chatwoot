// FORK: assignme - pending state for fast-assign concurrent request guard
import { ref, watch } from 'vue';

const PENDING_FALLBACK_MS = 15000;

export function normalizeAssignConversationIds(
  conversationId,
  selectedConversationIds
) {
  if (conversationId) {
    return Array.isArray(conversationId) ? conversationId : [conversationId];
  }

  return selectedConversationIds;
}

function normalizeAssigneeId(assigneeId) {
  if (assigneeId === null || assigneeId === undefined || assigneeId === '') {
    return null;
  }

  return Number(assigneeId);
}

function normalizeConversationId(conversationId) {
  return Number(conversationId);
}

export function useAssignMePending({ store } = {}) {
  const pendingAssignConversationIds = ref(new Map());
  const observedAssigneeIds = ref(new Map());
  const pendingFallbackTimers = new Map();

  function isAssignPending(conversationId) {
    return pendingAssignConversationIds.value.has(
      normalizeConversationId(conversationId)
    );
  }

  function clearPendingFallbackTimer(conversationId) {
    const timer = pendingFallbackTimers.get(conversationId);
    if (!timer) return;

    clearTimeout(timer);
    pendingFallbackTimers.delete(conversationId);
  }

  function clearAssignPending(conversationIds) {
    const nextPending = new Map(pendingAssignConversationIds.value);
    const nextObserved = new Map(observedAssigneeIds.value);

    conversationIds.forEach(id => {
      const normalizedId = normalizeConversationId(id);
      nextPending.delete(normalizedId);
      nextObserved.delete(normalizedId);
      clearPendingFallbackTimer(normalizedId);
    });

    pendingAssignConversationIds.value = nextPending;
    observedAssigneeIds.value = nextObserved;
  }

  function schedulePendingFallback(conversationId) {
    clearPendingFallbackTimer(conversationId);

    pendingFallbackTimers.set(
      conversationId,
      setTimeout(() => {
        if (pendingAssignConversationIds.value.has(conversationId)) {
          clearAssignPending([conversationId]);
        }
      }, PENDING_FALLBACK_MS)
    );
  }

  function shouldClearPending({
    expectedAssigneeId,
    currentAssigneeId,
    previousAssigneeId,
  }) {
    const expected = normalizeAssigneeId(expectedAssigneeId);
    const current = normalizeAssigneeId(currentAssigneeId);
    const previous =
      previousAssigneeId === undefined
        ? undefined
        : normalizeAssigneeId(previousAssigneeId);

    if (expected !== null && current === expected) {
      return true;
    }

    if (expected !== null && current !== null && current !== expected) {
      return true;
    }

    if (
      expected !== null &&
      previous !== undefined &&
      previous === expected &&
      current !== expected
    ) {
      return true;
    }

    if (previous !== null && previous !== undefined && current === null) {
      return true;
    }

    return false;
  }

  function syncPendingWithStore() {
    if (!pendingAssignConversationIds.value.size) return;

    const conversationList =
      store?.state?.conversations?.allConversations || [];
    const nextObserved = new Map(observedAssigneeIds.value);
    const idsToClear = [];

    pendingAssignConversationIds.value.forEach((expectedAssigneeId, id) => {
      const conversation = conversationList.find(
        item => normalizeConversationId(item.id) === id
      );
      const currentAssigneeId = conversation?.meta?.assignee?.id ?? null;
      const previousAssigneeId = observedAssigneeIds.value.get(id);

      if (
        shouldClearPending({
          expectedAssigneeId,
          currentAssigneeId,
          previousAssigneeId,
        })
      ) {
        idsToClear.push(id);
        return;
      }

      if (previousAssigneeId !== undefined || currentAssigneeId !== null) {
        nextObserved.set(id, currentAssigneeId);
      }
    });

    observedAssigneeIds.value = nextObserved;

    if (idsToClear.length) {
      clearAssignPending(idsToClear);
    }
  }

  function markAssignPendingUntilResolved(conversationIds, assigneeId) {
    const nextPending = new Map(pendingAssignConversationIds.value);
    const nextObserved = new Map(observedAssigneeIds.value);

    conversationIds.forEach(id => {
      const normalizedId = normalizeConversationId(id);
      nextPending.set(normalizedId, assigneeId);
      nextObserved.set(normalizedId, undefined);
      schedulePendingFallback(normalizedId);
    });

    pendingAssignConversationIds.value = nextPending;
    observedAssigneeIds.value = nextObserved;
    syncPendingWithStore();
  }

  function markAssignPending(conversationIds) {
    markAssignPendingUntilResolved(conversationIds, null);
  }

  function resolveAssignPending(conversationId, currentAssigneeId) {
    const normalizedId = normalizeConversationId(conversationId);
    const expectedAssigneeId =
      pendingAssignConversationIds.value.get(normalizedId);
    if (expectedAssigneeId === undefined) return;

    const previousAssigneeId = observedAssigneeIds.value.get(normalizedId);

    if (
      shouldClearPending({
        expectedAssigneeId,
        currentAssigneeId,
        previousAssigneeId,
      })
    ) {
      clearAssignPending([normalizedId]);
      return;
    }

    if (previousAssigneeId !== undefined || currentAssigneeId !== null) {
      observedAssigneeIds.value = new Map(observedAssigneeIds.value).set(
        normalizedId,
        currentAssigneeId ?? null
      );
    }
  }

  if (store) {
    watch(
      () => store.state?.conversations?.allConversations,
      () => syncPendingWithStore(),
      { deep: true }
    );

    watch(pendingAssignConversationIds, () => syncPendingWithStore(), {
      deep: true,
    });
  }

  return {
    isAssignPending,
    markAssignPending,
    markAssignPendingUntilResolved,
    clearAssignPending,
    resolveAssignPending,
  };
}
