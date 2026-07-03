import { onUnmounted, unref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { acquireEvolutionConnectionCable } from 'customDashboard/lib/evolution/evolutionCableRegistry';

export function subscribeEvolutionConnection(inboxId, onUpdate, context = {}) {
  const store = context.store;
  if (!inboxId || !store) return () => {};

  return acquireEvolutionConnectionCable({
    inboxId,
    pubsubToken: store.getters.getCurrentUser?.pubsub_token,
    accountId: store.getters.getCurrentAccountId,
    userId: store.getters.getCurrentUserID,
    onUpdate,
  });
}

export function useEvolutionConnectionCable(inboxIdRef, onUpdate) {
  const currentUser = useMapGetter('getCurrentUser');
  const accountId = useMapGetter('getCurrentAccountId');
  const userId = useMapGetter('getCurrentUserID');

  let release = null;

  const unsubscribe = () => {
    release?.();
    release = null;
  };

  watch(
    [() => unref(inboxIdRef), () => currentUser.value?.pubsub_token],
    ([inboxId]) => {
      unsubscribe();
      if (!inboxId) return;

      release = acquireEvolutionConnectionCable({
        inboxId,
        pubsubToken: currentUser.value?.pubsub_token,
        accountId: accountId.value,
        userId: userId.value,
        onUpdate,
      });
    },
    { immediate: true }
  );

  onUnmounted(unsubscribe);

  return { unsubscribe };
}
