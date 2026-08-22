import {
  useWhatsappCallSession,
  cleanupWhatsappSession,
} from 'dashboard/composables/useWhatsappCallSession';
import { teardownAllWavoipClients } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  endActiveCall as endSdkActiveCall,
  clearActiveCall as clearSdkActiveCall,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { removePendingOffer } from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import { isBrowserVoiceProvider } from 'customDashboard/lib/voice/browserVoiceProviders';
import { isInbound } from 'dashboard/helper/voice';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

export const VOICE_SESSION_REGISTRY = {
  [VOICE_CALL_PROVIDERS.WHATSAPP]: () => useWhatsappCallSession(),
};

let wavoipCallSession = null;

/** Registered from WavoipConnectionHost (setup) — do not call useI18n outside setup. */
export function registerWavoipCallSession(session) {
  wavoipCallSession = session || null;
}

export function getBrowserVoiceSession(provider) {
  if (provider === VOICE_CALL_PROVIDERS.WAVOIP) {
    return wavoipCallSession;
  }

  const factory = VOICE_SESSION_REGISTRY[provider];
  if (!factory) return null;
  return factory();
}

export function isWavoipVoiceCall(call) {
  return call?.provider === VOICE_CALL_PROVIDERS.WAVOIP;
}

export function isWhatsappVoiceCall(call) {
  return call?.provider === VOICE_CALL_PROVIDERS.WHATSAPP;
}

/** True when dismiss should SDK-reject (inbound Wavoip still ringing). */
export function shouldRejectWavoipInboundOnDismiss(call) {
  if (!isWavoipVoiceCall(call) || call?.isActive) return false;
  return (
    isInbound(call?.callDirection) ||
    call?.callDirection === VOICE_CALL_DIRECTION.INCOMING
  );
}

export function teardownWavoipActiveCall() {
  endSdkActiveCall();
  clearSdkActiveCall();
}

/**
 * Provider-specific cleanup after join/accept failure.
 * Returns whether the local store entry should be dismissed.
 *
 * Wavoip: tear down half-open SDK state but keep the ringing card so the agent
 * can retry after a WebSocket blip / offer timeout (dismiss would hide the UI
 * while the caller is still ringing).
 */
export function cleanupAfterBrowserVoiceJoinFailure(call, callSid) {
  if (isWavoipVoiceCall(call)) {
    teardownWavoipActiveCall();
    removePendingOffer(callSid);
    if (call?.wavoipOfferId) removePendingOffer(call.wavoipOfferId);
    return false;
  }
  if (isWhatsappVoiceCall(call) || isBrowserVoiceProvider(call?.provider)) {
    cleanupWhatsappSession();
    return false;
  }
  return false;
}

export function teardownBrowserVoiceSession(provider) {
  if (provider === VOICE_CALL_PROVIDERS.WAVOIP) {
    teardownWavoipActiveCall();
    return;
  }
  if (provider === VOICE_CALL_PROVIDERS.WHATSAPP) {
    cleanupWhatsappSession();
  }
}

export { teardownAllWavoipClients };
