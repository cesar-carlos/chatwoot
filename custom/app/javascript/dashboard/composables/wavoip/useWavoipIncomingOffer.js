import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import conversationI18n from 'dashboard/i18n/locale/en/conversation.json';
import {
  mapWavoipOfferToStoreEntry,
  reconcileWavoipStoreEntry,
} from 'customDashboard/lib/voice/callStoreMappers';
import {
  getWavoipClient,
  registerOfferUnsubscriber,
} from 'customDashboard/lib/wavoip/wavoipClientRegistry';

const pendingOffers = new Map();
const boundInboxIds = new Set();

const storeOffer = (offer, inboxId) => {
  pendingOffers.set(offer.id, { offer, inboxId });
};

export const getPendingOffer = callId => pendingOffers.get(callId)?.offer;

export const removePendingOffer = callId => {
  pendingOffers.delete(callId);
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
  callsStore.addCall(merged);
};

const wireOfferEvents = offer => {
  const dismiss = () => {
    removePendingOffer(offer.id);
    useCallsStore().dismissCall(offer.id);
  };

  offer.on?.('acceptedElsewhere', () => {
    useAlert(conversationI18n.CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE);
    dismiss();
  });
  offer.on?.('rejectedElsewhere', () => {
    useAlert(conversationI18n.CONVERSATION.WAVOIP_CALL.REJECTED_ELSEWHERE);
    dismiss();
  });
  offer.on?.('unanswered', dismiss);
  offer.on?.('ended', dismiss);
};

const bindOfferListener = inboxId => {
  if (boundInboxIds.has(inboxId)) return;
  const client = getWavoipClient(inboxId);
  if (!client?.on) return;

  const handler = offer => {
    if (!offer?.id) return;
    storeOffer(offer, inboxId);
    wireOfferEvents(offer);
    upsertIncomingOffer(offer, inboxId);
  };

  client.on('offer', handler);
  boundInboxIds.add(inboxId);
  registerOfferUnsubscriber(inboxId, () => {
    client.off?.('offer', handler);
    boundInboxIds.delete(inboxId);
  });
};

export function useWavoipIncomingOffer() {
  const attachToInbox = inboxId => {
    if (!inboxId) return;
    bindOfferListener(inboxId);
  };

  const acceptOffer = async callId => {
    const entry = pendingOffers.get(callId);
    if (!entry?.offer) throw new Error('Wavoip offer not found');
    return entry.offer.accept();
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
  };
}

export { pendingOffers };
