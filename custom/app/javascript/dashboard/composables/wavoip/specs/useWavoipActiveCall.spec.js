import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';

vi.mock('customDashboard/lib/wavoip/wavoipCallDiagnostics', () => ({
  wireCallDiagnostics: vi.fn(() => vi.fn()),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

import { useCallsStore } from 'dashboard/stores/calls';
import {
  clearActiveCall,
  clearRingingOutgoingCall,
  setActiveCall,
  setRingingOutgoingCall,
} from '../useWavoipActiveCall';
import { wireCallDiagnostics } from 'customDashboard/lib/wavoip/wavoipCallDiagnostics';

describe('useWavoipActiveCall', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    clearActiveCall();
    clearRingingOutgoingCall();
  });

  it('clears activeInboxId when clearing a ringing outgoing call', () => {
    const firstCall = { id: 'ring_1' };
    const secondCall = { id: 'ring_2' };

    setRingingOutgoingCall(firstCall, {
      providerCallId: 'ring_1',
      inboxId: 5,
    });
    clearRingingOutgoingCall();

    setRingingOutgoingCall(secondCall, {
      providerCallId: 'ring_2',
      inboxId: 99,
    });

    expect(wireCallDiagnostics).toHaveBeenLastCalledWith(
      secondCall,
      expect.objectContaining({ inboxId: 99 })
    );
  });

  it('tears down the active call when SDK emits status DISCONNECTED (2.6.3+)', () => {
    const handlers = {};
    const sdkCall = {
      connectionStatus: 'connected',
      on: vi.fn((event, handler) => {
        handlers[event] = handler;
      }),
      off: vi.fn(),
    };

    const store = useCallsStore();
    store.addCall({
      callSid: 'live_1',
      provider: 'wavoip',
      inboxId: 7,
      isActive: true,
    });

    setActiveCall(sdkCall, { providerCallId: 'live_1', inboxId: 7 });
    expect(handlers.status).toBeTypeOf('function');

    handlers.status('DISCONNECTED');

    expect(store.calls.some(c => c.callSid === 'live_1')).toBe(false);
  });
});
