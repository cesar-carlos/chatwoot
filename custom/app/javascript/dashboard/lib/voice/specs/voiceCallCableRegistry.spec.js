import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';

const { pendingOffers, removePendingOffer, isWavoipSdkCallOwned } = vi.hoisted(() => {
  const offers = new Map();
  return {
    pendingOffers: offers,
    removePendingOffer: callId => offers.delete(callId),
    isWavoipSdkCallOwned: vi.fn(() => false),
  };
});

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  endActiveCall: vi.fn(),
  clearActiveCall: vi.fn(),
  getActiveProviderCallId: vi.fn(() => null),
  isWavoipSdkCallOwned,
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

vi.mock('dashboard/composables/useCallSession', () => ({
  isCallJoining: vi.fn(() => false),
  isCallDismissed: vi.fn(() => false),
}));

vi.mock('dashboard/store', () => ({
  default: {
    getters: {
      getCurrentUserID: 99,
    },
  },
}));

import { useAlert } from 'dashboard/composables';
import { isCallDismissed, isCallJoining } from 'dashboard/composables/useCallSession';
import { createWavoipVoiceCableHandlers } from '../voiceCallCableRegistry';

const t = key => key;
const wavoipVoiceCableHandlers = createWavoipVoiceCableHandlers(t);

describe('wavoipVoiceCableHandlers', () => {
  beforeEach(() => {
    pendingOffers.clear();
    setActivePinia(createPinia());
  });

  describe('onIncoming', () => {
    beforeEach(() => {
      isCallDismissed.mockReturnValue(false);
    });

    it('does not re-add a call the agent dismissed locally', () => {
      isCallDismissed.mockReturnValue(true);
      const store = useCallsStore();

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'dismissed_001',
        id: 88,
        conversation_id: 12,
        inbox_id: 2,
        provider: 'wavoip',
      });

      expect(store.calls).toHaveLength(0);
    });

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
      expect(store.calls[0]?.awaitingSdkOffer).toBe(true);
    });
  });

  describe('onAccepted', () => {
    beforeEach(() => {
      isCallJoining.mockReturnValue(false);
    });

    it('dismisses ringing call when another agent accepted', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'acc_001',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onAccepted({
        call_id: 'acc_001',
        accepted_by_agent_id: 42,
      });

      expect(useAlert).toHaveBeenCalled();
      expect(store.calls.some(c => c.callSid === 'acc_001')).toBe(false);
    });

    it('does not dismiss when the current user accepted', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'acc_self',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onAccepted({
        call_id: 'acc_self',
        accepted_by_agent_id: 99,
      });

      expect(useAlert).not.toHaveBeenCalled();
      expect(store.calls.some(c => c.callSid === 'acc_self')).toBe(true);
    });

    it('does not dismiss while this tab is joining the call', () => {
      isCallJoining.mockReturnValue(true);
      const store = useCallsStore();
      store.addCall({
        callSid: 'acc_joining',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onAccepted({
        call_id: 'acc_joining',
        accepted_by_agent_id: 42,
      });

      expect(useAlert).not.toHaveBeenCalled();
      expect(store.calls.some(c => c.callSid === 'acc_joining')).toBe(true);
    });
  });

  describe('onEnded', () => {
    beforeEach(() => {
      isWavoipSdkCallOwned.mockReturnValue(false);
    });

    it('removes the call from the store and alerts handled_remotely', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'end_001',
        conversationId: 1,
        inboxId: 2,
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onEnded({
        call_id: 'end_001',
        end_reason: 'handled_remotely',
      });

      expect(useAlert).toHaveBeenCalled();
      expect(store.calls.some(c => c.callSid === 'end_001')).toBe(false);
    });

    it('keeps outbound ringing call when SDK still owns the session', () => {
      isWavoipSdkCallOwned.mockImplementation(callId => callId === 'out_ring_001');
      const store = useCallsStore();
      store.addCall({
        callSid: 'out_ring_001',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'outbound',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onEnded({
        call_id: 'out_ring_001',
        end_reason: 'no_answer',
      });

      expect(store.calls.some(c => c.callSid === 'out_ring_001')).toBe(true);
    });
  });
});
