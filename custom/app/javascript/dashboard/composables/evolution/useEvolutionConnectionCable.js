import { onUnmounted, unref, watch } from 'vue';
import { createConsumer } from '@rails/actioncable';
import { useMapGetter } from 'dashboard/composables/store';
import { normalizeEvolutionConnectionPayload } from 'customDashboard/lib/evolution/evolutionConnectionPayload';

let sharedConsumer;

function getConsumer() {
  if (!sharedConsumer) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    const url = websocketURL ? `${websocketURL}/cable` : undefined;
    sharedConsumer = createConsumer(url);
  }
  return sharedConsumer;
}

function createEvolutionSubscription({
  inboxId,
  pubsubToken,
  accountId,
  userId,
  onUpdate,
}) {
  if (!inboxId || !pubsubToken) return null;

  return getConsumer().subscriptions.create(
    {
      channel: 'EvolutionConnectionChannel',
      inbox_id: inboxId,
      pubsub_token: pubsubToken,
      account_id: accountId,
      user_id: userId,
    },
    {
      received(data) {
        const payload = normalizeEvolutionConnectionPayload(data);
        if (payload) onUpdate(payload);
      },
    }
  );
}

export function subscribeEvolutionConnection(inboxId, onUpdate, context = {}) {
  const store = context.store;
  if (!inboxId || !store) return () => {};

  const subscription = createEvolutionSubscription({
    inboxId,
    pubsubToken: store.getters.getCurrentUser?.pubsub_token,
    accountId: store.getters.getCurrentAccountId,
    userId: store.getters.getCurrentUserID,
    onUpdate,
  });

  return () => subscription?.unsubscribe();
}

export function useEvolutionConnectionCable(inboxIdRef, onUpdate) {
  const currentUser = useMapGetter('getCurrentUser');
  const accountId = useMapGetter('getCurrentAccountId');
  const userId = useMapGetter('getCurrentUserID');

  let subscription = null;

  const unsubscribe = () => {
    subscription?.unsubscribe();
    subscription = null;
  };

  const subscribe = inboxId => {
    unsubscribe();
    subscription = createEvolutionSubscription({
      inboxId,
      pubsubToken: currentUser.value?.pubsub_token,
      accountId: accountId.value,
      userId: userId.value,
      onUpdate,
    });
  };

  watch(
    [() => unref(inboxIdRef), () => currentUser.value?.pubsub_token],
    ([inboxId]) => subscribe(inboxId),
    { immediate: true }
  );

  onUnmounted(unsubscribe);

  return { unsubscribe };
}
