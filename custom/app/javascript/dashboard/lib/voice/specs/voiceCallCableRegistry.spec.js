import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';

const { pendingOffers, removePendingOffer } = vi.hoisted(() => {
  const offers = new Map();
  return {
    pendingOffers: offers,
    removePendingOffer: callId => offers.delete(callId),
  };
});

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  endActiveCall: vi.fn(),
  clearActiveCall: vi.fn(),
  getActiveProviderCallId: vi.fn(() => null),
}));

vi.mock('customDashboard/composables/wavoip/useWavoipIncomingOffer', () => ({
  pendingOffers,
  removePendingOffer,
}));

vi.mock('customDashboard/lib/wavoip/wavoipAcceptRecorder', () => ({
  flushAcceptedByRecording: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

import { wavoipVoiceCableHandlers } from '../voiceCallCableRegistry';

describe('wavoipVoiceCableHandlers', () => {
  beforeEach(() => {
    pendingOffers.clear();
    setActivePinia(createPinia());
  });

  describe('onIncoming', () => {
    it('merges pending SDK offer when cable arrives after offer', () => {
      const store = useCallsStore();
      pendingOffers.set('race_001', {
        offer: { id: 'race_001' },
        inboxId: 3,
      });

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'race_001',
        id: 55,
        conversation_id: 9,
        inbox_id: 3,
        provider: 'wavoip',
        caller: { name: 'Frank', phone: '+15556667777' },
      });

      const entry = store.calls.find(c => c.callSid === 'race_001');
      expect(entry).toMatchObject({
        callId: 55,
        conversationId: 9,
        wavoipOfferId: 'race_001',
        caller: { name: 'Frank', phone: '+15556667777' },
      });
    });

    it('accepts cable-only inbound when no SDK offer is pending', () => {
      const store = useCallsStore();

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'cable_only_001',
        id: 77,
        conversation_id: 11,
        inbox_id: 2,
        provider: 'wavoip',
      });

      expect(store.calls[0]?.callSid).toBe('cable_only_001');
      expect(store.calls[0]?.callId).toBe(77);
    });
  });
});
