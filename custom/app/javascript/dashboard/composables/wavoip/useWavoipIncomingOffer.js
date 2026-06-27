import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import { notifyIncomingWavoipOffer } from 'customDashboard/composables/wavoip/useWavoipNotifications';
import {
  findWavoipCallForOffer,
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

const storeOffer = (offer, inboxId, aliasCallSids = []) => {
  const entry = { offer, inboxId };
  pendingOffers.set(offer.id, entry);
  aliasCallSids.forEach(callSid => {
    if (callSid && callSid !== offer.id) pendingOffers.set(callSid, entry);
  });
};

export const getPendingOffer = callId => pendingOffers.get(callId)?.offer;

export const removePendingOffer = callId => {
  const entry = pendingOffers.get(callId);
  if (entry) {
    [...pendingOffers.entries()]
      .filter(([, value]) => value === entry)
      .forEach(([key]) => pendingOffers.delete(key));
  } else {
    pendingOffers.delete(callId);
  }

  const waiter = offerWaiters.get(callId);
  if (waiter) {
    clearTimeout(waiter.timer);
    offerWaiters.delete(callId);
    waiter.reject(new Error('Offer cancelled'));
  }
};

const resolveOfferWaiters = (offer, extraCallIds = []) => {
  [...new Set([offer.id, ...extraCallIds])].forEach(callId => {
    const waiter = offerWaiters.get(callId);
    if (!waiter) return;
    clearTimeout(waiter.timer);
    offerWaiters.delete(callId);
    waiter.resolve(offer);
  });
};

const dismissOfferFromStore = (offer, { alertKey, t } = {}) => {
  if (alertKey && t) useAlert(t(alertKey));

  const callsStore = useCallsStore();
  const callSids = new Set([offer.id]);
  callsStore.calls.forEach(call => {
    if (call.callSid === offer.id || call.wavoipOfferId === offer.id) {
      callSids.add(call.callSid);
    }
  });

  callSids.forEach(callSid => {
    removePendingOffer(callSid);
    callsStore.dismissCall(callSid);
  });
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

const mergeIncomingOffer = (offer, inboxId) => {
  const callsStore = useCallsStore();
  const existing = findWavoipCallForOffer(callsStore.calls, offer, inboxId);
  const mapped = mapWavoipOfferToStoreEntry(offer, {
    inboxId,
    conversationId: existing?.conversationId,
  });
  const merged = reconcileWavoipStoreEntry(existing, mapped);

  callsStore.addCall({
    ...merged,
    // Keep webhook call_id as callSid when cable arrived first.
    callSid: existing?.callSid || merged.callSid,
    wavoipOfferId: offer.id,
    awaitingSdkOffer: false,
  });

  if (existing && existing.callSid !== offer.id) {
    callsStore.dismissCall(offer.id);
  }
};

const wireOfferEvents = (offer, t) => {
  offer.on?.('acceptedElsewhere', () => {
    dismissOfferFromStore(offer, {
      alertKey: 'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE',
      t,
    });
  });
  offer.on?.('rejectedElsewhere', () => {
    dismissOfferFromStore(offer, {
      alertKey: 'CONVERSATION.WAVOIP_CALL.REJECTED_ELSEWHERE',
      t,
    });
  });
  offer.on?.('unanswered', () => {
    dismissOfferFromStore(offer, {
      alertKey: 'CONVERSATION.WAVOIP_CALL.CALLER_ENDED',
      t,
    });
  });
  offer.on?.('ended', () => {
    dismissOfferFromStore(offer, {
      alertKey: 'CONVERSATION.WAVOIP_CALL.CALLER_ENDED',
      t,
    });
  });
};

const bindOfferListener = (inboxId, t, store) => {
  if (boundInboxIds.has(inboxId)) return;
  const client = getWavoipClient(inboxId);
  if (!client?.on) return;

  const handler = offer => {
    if (!offer?.id) return;
    const callsStore = useCallsStore();
    const existing = findWavoipCallForOffer(callsStore.calls, offer, inboxId);
    const aliasCallSids =
      existing && existing.callSid !== offer.id ? [existing.callSid] : [];

    storeOffer(offer, inboxId, aliasCallSids);
    resolveOfferWaiters(offer, aliasCallSids);
    wireOfferEvents(offer, t);
    mergeIncomingOffer(offer, inboxId);
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
