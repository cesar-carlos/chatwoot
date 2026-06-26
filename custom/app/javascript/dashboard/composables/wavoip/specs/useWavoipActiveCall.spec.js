import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('customDashboard/lib/wavoip/wavoipCallDiagnostics', () => ({
  wireCallDiagnostics: vi.fn(),
}));

import { wireCallDiagnostics } from 'customDashboard/lib/wavoip/wavoipCallDiagnostics';
import {
  clearRingingOutgoingCall,
  setRingingOutgoingCall,
} from '../useWavoipActiveCall';

describe('useWavoipActiveCall', () => {
  beforeEach(() => {
    vi.clearAllMocks();
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
});
