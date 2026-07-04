import { createConsumer } from '@rails/actioncable';
import { normalizeEvolutionConnectionPayload } from 'customDashboard/lib/evolution/evolutionConnectionPayload';

const registry = new Map();
let sharedConsumer;

function getConsumer() {
  if (!sharedConsumer) {
    const { websocketURL = '' } = window.chatwootConfig || {};
    const url = websocketURL ? `${websocketURL}/cable` : undefined;
    sharedConsumer = createConsumer(url);
  }
  return sharedConsumer;
}

function createSubscription({ inboxId, pubsubToken, accountId, userId, listeners }) {
  if (!inboxId || !pubsubToken) return null;

  return getConsumer().subscriptions.create(
    {
      channel: 'EvolutionGoConnectionChannel',
      inbox_id: inboxId,
      pubsub_token: pubsubToken,
      account_id: accountId,
      user_id: userId,
    },
    {
      received(data) {
        const payload = normalizeEvolutionConnectionPayload(data);
        if (!payload) return;
        listeners.forEach(listener => listener(payload));
      },
    }
  );
}

export function subscribeEvolutionGoConnection(inboxId, onUpdate, context = {}) {
  const store = context.store;
  if (!inboxId || !store) return () => {};

  return acquireEvolutionGoConnectionCable({
    inboxId,
    pubsubToken: store.getters.getCurrentUser?.pubsub_token,
    accountId: store.getters.getCurrentAccountId,
    userId: store.getters.getCurrentUserID,
    onUpdate,
  });
}

export function acquireEvolutionGoConnectionCable({
  inboxId,
  pubsubToken,
  accountId,
  userId,
  onUpdate,
}) {
  if (!inboxId || !pubsubToken || !onUpdate) return () => {};

  const key = String(inboxId);
  let entry = registry.get(key);

  if (!entry) {
    const listeners = new Set();
    const subscription = createSubscription({
      inboxId,
      pubsubToken,
      accountId,
      userId,
      listeners,
    });
    entry = { listeners, subscription };
    registry.set(key, entry);
  }

  entry.listeners.add(onUpdate);

  return () => {
    entry.listeners.delete(onUpdate);
    if (entry.listeners.size === 0) {
      entry.subscription?.unsubscribe();
      registry.delete(key);
    }
  };
}
