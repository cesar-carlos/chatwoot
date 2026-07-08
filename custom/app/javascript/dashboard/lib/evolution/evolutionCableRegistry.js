import { createConsumer } from '@rails/actioncable';
import { useAlert } from 'dashboard/composables';
import i18n from 'dashboard/i18n';
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

function disconnectSharedConsumerIfIdle() {
  if (registry.size === 0 && sharedConsumer) {
    sharedConsumer.disconnect();
    sharedConsumer = null;
  }
}

function createEvolutionSubscription({
  inboxId,
  pubsubToken,
  accountId,
  userId,
  listeners,
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
        if (!payload) return;
        listeners.forEach(listener => listener(payload));
      },
    }
  );
}

export function acquireEvolutionConnectionCable({
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
    const subscription = createEvolutionSubscription({
      inboxId,
      pubsubToken,
      accountId,
      userId,
      listeners,
    });
    entry = { listeners, subscription, pubsubToken };
    registry.set(key, entry);
  } else if (entry.pubsubToken !== pubsubToken) {
    entry.subscription?.unsubscribe();
    entry.listeners = entry.listeners || new Set();
    entry.subscription = createEvolutionSubscription({
      inboxId,
      pubsubToken,
      accountId,
      userId,
      listeners: entry.listeners,
    });
    entry.pubsubToken = pubsubToken;
  }

  entry.listeners.add(onUpdate);

  return () => {
    entry.listeners.delete(onUpdate);
    if (entry.listeners.size === 0) {
      entry.subscription?.unsubscribe();
      registry.delete(key);
      disconnectSharedConsumerIfIdle();
    }
  };
}

export function onEvolutionConnectionClosed(data) {
  useAlert(
    i18n.global.t('INBOX_MGMT.EVOLUTION.SETTINGS.HEALTH.DISCONNECTED_ALERT', {
      inbox: data.inbox_name,
    })
  );
}
