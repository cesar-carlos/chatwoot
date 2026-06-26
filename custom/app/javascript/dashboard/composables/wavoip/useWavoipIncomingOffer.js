import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import { notifyIncomingWavoipOffer } from 'customDashboard/composables/wavoip/useWavoipNotifications';
import {
  mapWavoipOfferToStoreEntry,
  reconcileWavoipStoreEntry,
} from 'customDashboard/lib/voice/callStoreMappers';
import {
  getWavoipClient,
  registerOfferUnsubscriber,
} from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { unwrapWavoipSdkResult } from 'customDashboard/lib/wavoip/wavoipSdkResult';

const pendingOffers = new Map();
const boundInboxIds = new Set();
const offerWaiters = new Map();

const storeOffer = (offer, inboxId) => {
  pendingOffers.set(offer.id, { offer, inboxId });
};

export const getPendingOffer = callId => pendingOffers.get(callId)?.offer;

export const removePendingOffer = callId => {
  pendingOffers.delete(callId);
  const waiter = offerWaiters.get(callId);
  if (waiter) {
    clearTimeout(waiter.timer);
    offerWaiters.delete(callId);
    waiter.reject(new Error('Offer cancelled'));
  }
};

const resolveOfferWaiters = offer => {
  const waiter = offerWaiters.get(offer.id);
  if (!waiter) return;
  clearTimeout(waiter.timer);
  offerWaiters.delete(offer.id);
  waiter.resolve(offer);
};

export const waitForPendingOffer = (callId, timeoutMs = 10_000) => {
  if (pendingOffers.has(callId)) {
    return Promise.resolve(pendingOffers.get(callId).offer);
  }

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      offerWaiters.delete(callId);
      reject(new Error('Wavoip offer timeout'));
    }, timeoutMs);
    offerWaiters.set(callId, { resolve, reject, timer });
  });
};

const reconcileAwaitingSdkOffer = (offer, inboxId) => {
  const callsStore = useCallsStore();
  const existing = callsStore.calls.find(
    c =>
      c.callSid === offer.id ||
      c.wavoipOfferId === offer.id ||
      (c.awaitingSdkOffer && c.callSid === offer.id)
  );
  if (!existing) return;

  const mapped = mapWavoipOfferToStoreEntry(offer, {
    inboxId,
    conversationId: existing.conversationId,
  });
  callsStore.addCall({
    ...reconcileWavoipStoreEntry(existing, mapped),
    awaitingSdkOffer: false,
  });
};

const upsertIncomingOffer = (offer, inboxId) => {
  const callsStore = useCallsStore();
  const existing = callsStore.calls.find(
    c => c.callSid === offer.id || c.wavoipOfferId === offer.id
  );
  const mapped = mapWavoipOfferToStoreEntry(offer, {
    inboxId,
    conversationId: existing?.conversationId,
  });
  const merged = reconcileWavoipStoreEntry(existing, mapped);
  callsStore.addCall({ ...merged, awaitingSdkOffer: false });
};

const wireOfferEvents = (offer, t) => {
  const dismiss = () => {
    removePendingOffer(offer.id);
    useCallsStore().dismissCall(offer.id);
  };

  offer.on?.('acceptedElsewhere', () => {
    useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE'));
    dismiss();
  });
  offer.on?.('rejectedElsewhere', () => {
    useAlert(t('CONVERSATION.WAVOIP_CALL.REJECTED_ELSEWHERE'));
    dismiss();
  });
  offer.on?.('unanswered', dismiss);
  offer.on?.('ended', dismiss);
};

const bindOfferListener = (inboxId, t, store) => {
  if (boundInboxIds.has(inboxId)) return;
  const client = getWavoipClient(inboxId);
  if (!client?.on) return;

  const handler = offer => {
    if (!offer?.id) return;
    storeOffer(offer, inboxId);
    resolveOfferWaiters(offer);
    wireOfferEvents(offer, t);
    reconcileAwaitingSdkOffer(offer, inboxId);
    upsertIncomingOffer(offer, inboxId);
    const inbox = store?.getters?.['inboxes/getInbox']?.(inboxId);
    notifyIncomingWavoipOffer(offer, inbox);
  };

  client.on('offer', handler);
  boundInboxIds.add(inboxId);
  registerOfferUnsubscriber(inboxId, () => {
    client.off?.('offer', handler);
    boundInboxIds.delete(inboxId);
  });
};

export function useWavoipIncomingOffer() {
  const { t } = useI18n();
  const store = useStore();

  const attachToInbox = inboxId => {
    if (!inboxId) return;
    bindOfferListener(inboxId, t, store);
  };

  const acceptOffer = async callId => {
    const entry = pendingOffers.get(callId);
    if (!entry?.offer) throw new Error('Wavoip offer not found');

    const result = await entry.offer.accept();
    const { call, err } = unwrapWavoipSdkResult(result);
    if (err || !call) {
      throw new Error(
        typeof err === 'string' ? err : err?.message || 'Wavoip accept failed'
      );
    }
    return call;
  };

  const rejectOffer = async callId => {
    const entry = pendingOffers.get(callId);
    if (!entry?.offer) return;
    try {
      await entry.offer.reject?.();
    } finally {
      removePendingOffer(callId);
    }
  };

  return {
    attachToInbox,
    acceptOffer,
    rejectOffer,
    getPendingOffer,
    waitForPendingOffer,
  };
}

export { pendingOffers };
