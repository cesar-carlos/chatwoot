import {
  useWhatsappCallSession,
  cleanupWhatsappSession,
} from 'dashboard/composables/useWhatsappCallSession';
import { useWavoipCallSession } from 'customDashboard/composables/wavoip/useWavoipCallSession';
import { teardownAllWavoipClients } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  endActiveCall as endSdkActiveCall,
  clearActiveCall as clearSdkActiveCall,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

export const VOICE_SESSION_REGISTRY = {
  [VOICE_CALL_PROVIDERS.WHATSAPP]: () => useWhatsappCallSession(),
  [VOICE_CALL_PROVIDERS.WAVOIP]: () => useWavoipCallSession(),
};

export function getBrowserVoiceSession(provider) {
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
