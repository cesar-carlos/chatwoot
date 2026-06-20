import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';

const {
  teardownAllWavoipClients,
  cleanupWhatsappSession,
  endSdkActiveCall,
  clearSdkActiveCall,
} = vi.hoisted(() => ({
  teardownAllWavoipClients: vi.fn(),
  cleanupWhatsappSession: vi.fn(),
  endSdkActiveCall: vi.fn(),
  clearSdkActiveCall: vi.fn(),
}));

vi.mock('customDashboard/lib/wavoip/wavoipClientRegistry', () => ({
  teardownAllWavoipClients,
}));

vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: vi.fn(),
  cleanupWhatsappSession,
}));

vi.mock('customDashboard/composables/wavoip/useWavoipCallSession', () => ({
  useWavoipCallSession: vi.fn(),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  endActiveCall: endSdkActiveCall,
  clearActiveCall: clearSdkActiveCall,
}));

import {
  teardownBrowserVoiceSession,
  teardownWavoipActiveCall,
} from '../voiceSessionRegistry';

describe('voiceSessionRegistry', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setActivePinia(createPinia());
  });

  describe('teardownWavoipActiveCall', () => {
    it('ends only the active SDK call without disconnecting all inboxes', () => {
      teardownWavoipActiveCall();

      expect(endSdkActiveCall).toHaveBeenCalledTimes(1);
      expect(clearSdkActiveCall).toHaveBeenCalledTimes(1);
      expect(teardownAllWavoipClients).not.toHaveBeenCalled();
    });
  });

  describe('teardownBrowserVoiceSession', () => {
    it('scopes Wavoip teardown to the active call only', () => {
      teardownBrowserVoiceSession(VOICE_CALL_PROVIDERS.WAVOIP);

      expect(endSdkActiveCall).toHaveBeenCalledTimes(1);
      expect(clearSdkActiveCall).toHaveBeenCalledTimes(1);
      expect(teardownAllWavoipClients).not.toHaveBeenCalled();
    });

    it('cleans up WhatsApp session without touching Wavoip registry', () => {
      teardownBrowserVoiceSession(VOICE_CALL_PROVIDERS.WHATSAPP);

      expect(cleanupWhatsappSession).toHaveBeenCalledTimes(1);
      expect(teardownAllWavoipClients).not.toHaveBeenCalled();
    });
  });
});
