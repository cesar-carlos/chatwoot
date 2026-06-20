import { useI18n } from 'vue-i18n';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
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

const bindOfferListener = (inboxId, t) => {
  if (boundInboxIds.has(inboxId)) return;
  const client = getWavoipClient(inboxId);
  if (!client?.on) return;

  const handler = offer => {
    if (!offer?.id) return;
    storeOffer(offer, inboxId);
    wireOfferEvents(offer, t);
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
  const { t } = useI18n();

  const attachToInbox = inboxId => {
    if (!inboxId) return;
    bindOfferListener(inboxId, t);
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
