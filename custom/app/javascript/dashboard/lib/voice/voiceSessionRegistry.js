import {
  useWhatsappCallSession,
  cleanupWhatsappSession,
} from 'dashboard/composables/useWhatsappCallSession';
import { teardownAllWavoipClients } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  endActiveCall as endSdkActiveCall,
  clearActiveCall as clearSdkActiveCall,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
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

export function teardownWavoipActiveCall() {
  endSdkActiveCall();
  clearSdkActiveCall();
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
