import { createWavoipClient } from 'customDashboard/lib/wavoip/wavoipSdkPort';
import { clearWavoipMediaForInbox } from 'customDashboard/composables/wavoip/useWavoipMedia';
import {
  pendingOffers,
  removePendingOffer,
} from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';

const clients = new Map();

export function getWavoipClientEntry(inboxId) {
  return clients.get(inboxId);
}

export function getWavoipClient(inboxId) {
  return clients.get(inboxId)?.client;
}

export async function disconnectWavoipInbox(inboxId) {
  const entry = clients.get(inboxId);
  if (!entry) return;

  entry.offerUnsubscribers.forEach(unsub => {
    try {
      unsub();
    } catch (_) {
      /* noop */
    }
  });

  entry.deviceUnsubscribers?.forEach(unsub => {
    try {
      unsub();
    } catch (_) {
      /* noop */
    }
  });

  try {
    entry.client?.removeDevices?.([entry.token]);
  } catch (_) {
    /* noop */
  }

  [...pendingOffers.entries()]
    .filter(([, offerEntry]) => offerEntry.inboxId === inboxId)
    .map(([callId]) => callId)
    .forEach(callId => removePendingOffer(callId));

  clearWavoipMediaForInbox(inboxId);
  clients.delete(inboxId);
}

export async function connectWavoipInbox(inboxId, deviceToken) {
  if (!inboxId || !deviceToken) return null;

  const existing = clients.get(inboxId);
  if (existing?.token === deviceToken) return existing.client;

  if (existing) await disconnectWavoipInbox(inboxId);

  const client = await createWavoipClient({ tokens: [deviceToken] });
  clients.set(inboxId, {
    client,
    token: deviceToken,
    inboxId,
    offerUnsubscribers: [],
    deviceUnsubscribers: [],
  });
  return client;
}

export function registerOfferUnsubscriber(inboxId, unsubscribe) {
  const entry = clients.get(inboxId);
  if (!entry || !unsubscribe) return;
  entry.offerUnsubscribers.push(unsubscribe);
}

export function registerDeviceUnsubscriber(inboxId, unsubscribe) {
  const entry = clients.get(inboxId);
  if (!entry || !unsubscribe) return;
  entry.deviceUnsubscribers.push(unsubscribe);
}

export async function teardownAllWavoipClients() {
  const inboxIds = [...clients.keys()];
  await Promise.all(inboxIds.map(id => disconnectWavoipInbox(id)));
}
