import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';

const { isWavoipSdkCallOwned } = vi.hoisted(() => ({
  isWavoipSdkCallOwned: vi.fn(() => false),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  isWavoipSdkCallOwned,
}));

vi.mock('customDashboard/lib/voice/voiceSessionRegistry', () => ({
  teardownBrowserVoiceSession: vi.fn(),
}));

vi.mock('customDashboard/lib/voice/browserVoiceProviders', () => ({
  isBrowserVoiceProvider: vi.fn(() => false),
}));

vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: { endClientCall: vi.fn() },
}));

import { useCallsStore } from '../calls';

describe('useCallsStore — Wavoip outbound terminal status', () => {
  beforeEach(() => {
    isWavoipSdkCallOwned.mockReturnValue(false);
    setActivePinia(createPinia());
  });

  it('defers removeCall when SDK still owns outbound ringing call', () => {
    isWavoipSdkCallOwned.mockImplementation(callSid => callSid === 'out_001');
    const store = useCallsStore();
    store.addCall({
      callSid: 'out_001',
      conversationId: 1,
      inboxId: 2,
      callDirection: 'outbound',
      provider: 'wavoip',
    });

    store.handleCallStatusChanged({ callSid: 'out_001', status: 'no-answer' });

    expect(store.calls.some(c => c.callSid === 'out_001')).toBe(true);
  });

  it('removes outbound call on terminal status when SDK does not own it', () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'out_002',
      conversationId: 1,
      inboxId: 2,
      callDirection: 'outbound',
      provider: 'wavoip',
    });

    store.handleCallStatusChanged({ callSid: 'out_002', status: 'completed' });

    expect(store.calls.some(c => c.callSid === 'out_002')).toBe(false);
  });
});
