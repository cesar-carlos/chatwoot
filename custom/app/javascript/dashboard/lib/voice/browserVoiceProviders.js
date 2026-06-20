import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

const BROWSER_VOICE_PROVIDERS = new Set([
  VOICE_CALL_PROVIDERS.WHATSAPP,
  VOICE_CALL_PROVIDERS.WAVOIP,
]);

export function isBrowserVoiceProvider(provider) {
  return BROWSER_VOICE_PROVIDERS.has(provider);
}
