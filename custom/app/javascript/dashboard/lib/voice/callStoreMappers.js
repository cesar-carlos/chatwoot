import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { normalizeCallDirection } from 'customDashboard/lib/voice/voiceCallDirection';

export function mapCableToStoreEntry(data) {
  const callDirection = normalizeCallDirection(data.call_direction);

  return {
    callSid: data.call_id,
    callId: data.id,
    provider: data.provider || VOICE_CALL_PROVIDERS.WAVOIP,
    conversationId: data.conversation_id,
    inboxId: data.inbox_id,
    callDirection,
    caller: data.caller,
    wavoipOfferId: data.call_id,
  };
}

export function mapWavoipOfferToStoreEntry(
  offer,
  { inboxId, conversationId } = {}
) {
  const peer = offer?.peer || {};
  return {
    callSid: offer.id,
    provider: VOICE_CALL_PROVIDERS.WAVOIP,
    wavoipOfferId: offer.id,
    callDirection: VOICE_CALL_DIRECTION.INBOUND,
    inboxId,
    conversationId,
    caller: {
      name: peer.displayName || peer.phone,
      phone: peer.phone,
      avatar: peer.profilePicture,
    },
  };
}

export function mergeStoreEntries(existing, incoming) {
  const next = { ...existing, ...incoming };
  if (existing?.caller && !incoming?.caller) next.caller = existing.caller;
  if (existing?.callId && !incoming?.callId) next.callId = existing.callId;
  if (existing?.conversationId && !incoming?.conversationId) {
    next.conversationId = existing.conversationId;
  }
  if (existing?.inboxId && !incoming?.inboxId) next.inboxId = existing.inboxId;
  if (existing?.wavoipOfferId && !incoming?.wavoipOfferId) {
    next.wavoipOfferId = existing.wavoipOfferId;
  }
  return next;
}

export function reconcileWavoipStoreEntry(existing, incoming) {
  if (!existing) return incoming;
  const merged = mergeStoreEntries(existing, incoming);
  if (existing.callDirection === VOICE_CALL_DIRECTION.OUTBOUND) {
    merged.callDirection = VOICE_CALL_DIRECTION.OUTBOUND;
  }
  return merged;
}

/** Match cable + SDK rows when whatsapp_call_id and Offer.id diverge. */
export function findWavoipCallForOffer(calls, offer, inboxId) {
  if (!offer?.id) return null;

  const directMatch = calls.find(
    c =>
      c.provider === VOICE_CALL_PROVIDERS.WAVOIP &&
      (c.callSid === offer.id || c.wavoipOfferId === offer.id)
  );
  if (directMatch) return directMatch;

  const awaiting = calls.filter(
    c =>
      c.provider === VOICE_CALL_PROVIDERS.WAVOIP &&
      c.awaitingSdkOffer &&
      c.inboxId === inboxId &&
      !c.isActive
  );
  return awaiting.length === 1 ? awaiting[0] : null;
}

/**
 * Mirror of `findWavoipCallForOffer` for the opposite arrival order: an SDK
 * `offer` already created a store row (keyed by `offer.id`) before the
 * webhook/cable event confirms the same call under `whatsapp_call_id`. Without
 * this, `onIncoming` would create a second, duplicate widget until something
 * else reconciles the two ids later.
 */
export function findWavoipCallForCableEvent(calls, data) {
  if (!data?.call_id) return null;

  const directMatch = calls.find(
    c =>
      c.provider === VOICE_CALL_PROVIDERS.WAVOIP &&
      (c.callSid === data.call_id ||
        c.wavoipOfferId === data.call_id ||
        (data.id != null && c.callId === data.id))
  );
  if (directMatch) return directMatch;

  const awaitingCableConfirmation = calls.filter(
    c =>
      c.provider === VOICE_CALL_PROVIDERS.WAVOIP &&
      c.inboxId === data.inbox_id &&
      c.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND &&
      !c.isActive &&
      !c.callId
  );
  return awaitingCableConfirmation.length === 1
    ? awaitingCableConfirmation[0]
    : null;
}
