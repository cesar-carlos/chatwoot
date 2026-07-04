import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  getRingingProviderCallId,
  isOutboundInitiationActive,
  isWavoipSdkCallOwned,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { findWavoipCallForOffer } from 'customDashboard/lib/voice/callStoreMappers';
import { isOutboundCallDirection } from 'customDashboard/lib/voice/voiceCallDirection';

export const isAgentInitiatedWavoipCallId = callId =>
  !!callId &&
  (isWavoipSdkCallOwned(callId) || getRingingProviderCallId() === callId);

export const isAgentInitiatedWavoipStoreCall = call => {
  if (!call || call.provider !== VOICE_CALL_PROVIDERS.WAVOIP) return false;
  if (call.callDirection === VOICE_CALL_DIRECTION.OUTBOUND) return true;
  return (
    isAgentInitiatedWavoipCallId(call.callSid) ||
    isAgentInitiatedWavoipCallId(call.wavoipOfferId)
  );
};

/** SDK `offer` also fires for outbound startCall; skip inbound UI/notifications. */
export const isWavoipOutboundCablePayload = data =>
  isOutboundCallDirection(data?.call_direction);

export const shouldIgnoreInboundWavoipOffer = (offer, { calls = [], inboxId } = {}) => {
  if (!offer?.id) return true;
  if (isOutboundInitiationActive(inboxId)) return true;
  if (isAgentInitiatedWavoipCallId(offer.id)) return true;

  const existing = findWavoipCallForOffer(calls, offer, inboxId);
  return isAgentInitiatedWavoipStoreCall(existing);
};

export const shouldIgnoreInboundWavoipCable = (data, { calls = [] } = {}) => {
  if (!data?.call_id) return true;
  if (isOutboundInitiationActive(data.inbox_id)) return true;
  if (isWavoipOutboundCablePayload(data)) return true;
  if (isAgentInitiatedWavoipCallId(data.call_id)) return true;

  const existing = calls.find(
    c =>
      c.callSid === data.call_id ||
      c.wavoipOfferId === data.call_id ||
      (c.callId && c.callId === data.id)
  );
  return isAgentInitiatedWavoipStoreCall(existing);
};
