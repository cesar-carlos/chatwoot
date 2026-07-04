import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  isWavoipSdkCallOwned: vi.fn(() => false),
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

describe('useCallsStore#addCall — id alias reconciliation', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  it('merges into the existing row when only wavoipOfferId matches (divergent callSid)', () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'sdk_offer_id',
      wavoipOfferId: 'sdk_offer_id',
      provider: 'wavoip',
      inboxId: 2,
      awaitingSdkOffer: false,
    });

    store.addCall({
      callSid: 'webhook_call_id',
      wavoipOfferId: 'sdk_offer_id',
      callId: 55,
      provider: 'wavoip',
      inboxId: 2,
      conversationId: 9,
    });

    expect(store.calls).toHaveLength(1);
    // The SDK-origin callSid stays canonical; the webhook's id lands in callId.
    expect(store.calls[0]).toMatchObject({
      callSid: 'sdk_offer_id',
      wavoipOfferId: 'sdk_offer_id',
      callId: 55,
      conversationId: 9,
    });
  });

  it('merges into the existing row when only callId (DB id) matches', () => {
    const store = useCallsStore();
    store.addCall({
      callSid: 'temp_sid',
      callId: 77,
      provider: 'wavoip',
      inboxId: 2,
    });

    store.addCall({
      callSid: 'different_sid',
      callId: 77,
      provider: 'wavoip',
      inboxId: 2,
      conversationId: 11,
    });

    expect(store.calls).toHaveLength(1);
    expect(store.calls[0].callSid).toBe('temp_sid');
    expect(store.calls[0].conversationId).toBe(11);
  });

  it('still creates a new row when no id matches at all', () => {
    const store = useCallsStore();
    store.addCall({ callSid: 'a', wavoipOfferId: 'a', provider: 'wavoip' });
    store.addCall({ callSid: 'b', wavoipOfferId: 'b', provider: 'wavoip' });

    expect(store.calls).toHaveLength(2);
  });
});
