import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';

vi.mock('customDashboard/lib/wavoip/wavoipCallDiagnostics', () => ({
  wireCallDiagnostics: vi.fn(() => vi.fn()),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipIncomingOffer', () => ({
  removePendingOffer: vi.fn(),
}));

import { removePendingOffer } from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import { setActiveCall, clearActiveCall } from '../useWavoipActiveCall';

describe('useWavoipActiveCall ended handler', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    clearActiveCall();
  });

  it('removes the active call from the store when the SDK emits ended', () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'webhook_call_id',
      wavoipOfferId: 'sdk_offer_id',
      provider: 'wavoip',
      isActive: true,
    });

    const sdkCall = {
      on: vi.fn((event, handler) => {
        if (event === 'ended') sdkCall.endedHandler = handler;
      }),
      off: vi.fn(),
    };

    setActiveCall(sdkCall, {
      providerCallId: 'webhook_call_id',
      inboxId: 3,
    });
    store.setCallActive('webhook_call_id');

    sdkCall.endedHandler();

    expect(store.calls).toHaveLength(0);
    expect(removePendingOffer).toHaveBeenCalled();
  });
});
