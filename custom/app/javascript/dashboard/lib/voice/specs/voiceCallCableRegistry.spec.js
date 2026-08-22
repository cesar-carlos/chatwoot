import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';

const {
  pendingOffers,
  removePendingOffer,
  isWavoipSdkCallOwned,
  getRingingProviderCallId,
  isOutboundInitiationActive,
} = vi.hoisted(() => {
  const offers = new Map();
  return {
    pendingOffers: offers,
    removePendingOffer: callId => offers.delete(callId),
    isWavoipSdkCallOwned: vi.fn(() => false),
    getRingingProviderCallId: vi.fn(() => null),
    isOutboundInitiationActive: vi.fn(() => false),
  };
});

vi.mock('customDashboard/composables/wavoip/useWavoipActiveCall', () => ({
  endActiveCall: vi.fn(),
  clearActiveCall: vi.fn(),
  getActiveProviderCallId: vi.fn(() => null),
  getRingingProviderCallId: vi.fn(() => null),
  isOutboundInitiationActive,
  isWavoipSdkCallOwned,
}));

vi.mock('customDashboard/composables/wavoip/useWavoipIncomingOffer', () => ({
  pendingOffers,
  removePendingOffer,
}));

vi.mock('customDashboard/lib/wavoip/wavoipAcceptRecorder', () => ({
  flushAcceptedByRecording: vi.fn(),
}));

vi.mock('customDashboard/lib/wavoip/wavoipInboundConversation', () => ({
  reopenWavoipInboundConversation: vi.fn(),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('dashboard/helper/voiceCallDismissed', () => ({
  isCallDismissed: vi.fn(() => false),
  markCallDismissed: vi.fn(),
}));

vi.mock('dashboard/store', () => ({
  default: {
    getters: {
      getCurrentUserID: 99,
    },
  },
}));

import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { useAlert } from 'dashboard/composables';
import {
  clearActiveCall,
  endActiveCall,
  getActiveProviderCallId,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { isCallDismissed } from 'dashboard/helper/voiceCallDismissed';
import { createWavoipVoiceCableHandlers } from '../voiceCallCableRegistry';
import { reopenWavoipInboundConversation } from 'customDashboard/lib/wavoip/wavoipInboundConversation';

const t = key => key;
const wavoipVoiceCableHandlers = createWavoipVoiceCableHandlers(t);

describe('wavoipVoiceCableHandlers', () => {
  beforeEach(() => {
    pendingOffers.clear();
    setActivePinia(createPinia());
    getActiveProviderCallId.mockReturnValue(null);
    isWavoipSdkCallOwned.mockReturnValue(false);
    endActiveCall.mockClear();
    useAlert.mockClear();
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

    it('ignores escalated re-ring when the call is already active or dismissed', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'esc_001',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });
      store.setCallActive('esc_001');

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'esc_001',
        id: 90,
        conversation_id: 1,
        inbox_id: 2,
        provider: 'wavoip',
        escalated: true,
      });

      expect(store.calls).toHaveLength(1);
      expect(store.calls[0].isActive).toBe(true);
    });

    it('marks escalated flag on store entry for first escalated ring', () => {
      const store = useCallsStore();

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'esc_new',
        id: 91,
        conversation_id: 3,
        inbox_id: 2,
        provider: 'wavoip',
        call_direction: 'inbound',
        escalated: true,
        caller: { name: 'Bob', phone: '+5511' },
      });

      expect(store.calls[0].escalated).toBe(true);
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

    it('reopens the conversation when inbound cable includes conversation_id', () => {
      const store = useCallsStore();

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'cable_only_001',
        id: 77,
        conversation_id: 11,
        inbox_id: 2,
        provider: 'wavoip',
      });

      expect(reopenWavoipInboundConversation).toHaveBeenCalledWith(11);
      expect(store.calls[0]?.callSid).toBe('cable_only_001');
    });

    it('accepts cable-only inbound when no SDK offer is pending', () => {
      reopenWavoipInboundConversation.mockClear();
      const store = useCallsStore();

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'cable_only_002',
        id: 78,
        conversation_id: 12,
        inbox_id: 2,
        provider: 'wavoip',
      });

      expect(store.calls[0]?.callSid).toBe('cable_only_002');
      expect(store.calls[0]?.callId).toBe(78);
      expect(store.calls[0]?.awaitingSdkOffer).toBe(true);
    });

    it('reconciles onto the SDK-origin row when the webhook call_id differs from offer.id', () => {
      const store = useCallsStore();
      // Simulates an SDK offer that already created a row under its own id,
      // with no DB call id yet (mirrors mapWavoipOfferToStoreEntry's shape).
      store.addCall({
        callSid: 'sdk_offer_id',
        wavoipOfferId: 'sdk_offer_id',
        provider: 'wavoip',
        inboxId: 2,
        callDirection: VOICE_CALL_DIRECTION.INBOUND,
        awaitingSdkOffer: false,
      });

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'webhook_call_id_divergent',
        id: 123,
        conversation_id: 20,
        inbox_id: 2,
        provider: 'wavoip',
      });

      expect(store.calls).toHaveLength(1);
      expect(store.calls[0]).toMatchObject({
        callSid: 'sdk_offer_id',
        callId: 123,
        conversationId: 20,
      });
    });

    it('ignores cable when payload marks outbound direction', () => {
      const store = useCallsStore();

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'server_out',
        id: 91,
        conversation_id: 6,
        inbox_id: 2,
        provider: 'wavoip',
        call_direction: 'outbound',
      });

      expect(store.calls).toHaveLength(0);
    });

    it('does not add inbound cable row for agent-initiated outbound call', () => {
      getRingingProviderCallId.mockReturnValue('out_cable');
      const store = useCallsStore();
      store.addCall({
        callSid: 'out_cable',
        conversationId: 5,
        inboxId: 2,
        callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onIncoming({
        call_id: 'out_cable',
        id: 90,
        conversation_id: 5,
        inbox_id: 2,
        provider: 'wavoip',
      });

      expect(store.calls).toHaveLength(1);
      expect(store.calls[0].callDirection).toBe(VOICE_CALL_DIRECTION.OUTBOUND);
      expect(store.calls[0].callId).toBeUndefined();
    });
  });

  describe('onAccepted', () => {
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

    it('includes agent name in accepted elsewhere alert when provided', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'acc_named',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onAccepted({
        call_id: 'acc_named',
        accepted_by_agent_id: 42,
        accepted_by_agent_name: 'Maria',
      });

      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE_BY'
      );
      expect(store.calls.some(c => c.callSid === 'acc_named')).toBe(false);
    });

    it('does not dismiss when the current user accepted and owns the SDK call', () => {
      isWavoipSdkCallOwned.mockReturnValue(true);
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

    it('silently dismisses when the current user accepted in another tab', () => {
      isWavoipSdkCallOwned.mockReturnValue(false);
      const store = useCallsStore();
      store.addCall({
        callSid: 'acc_other_tab',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onAccepted({
        call_id: 'acc_other_tab',
        accepted_by_agent_id: 99,
        accepted_by_agent_name: 'Self',
      });

      expect(useAlert).not.toHaveBeenCalled();
      expect(store.calls.some(c => c.callSid === 'acc_other_tab')).toBe(false);
    });

    it('dismisses while this tab is joining when another agent accepted', () => {
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
        accepted_by_agent_name: 'Maria',
      });

      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE_BY'
      );
      expect(store.calls.some(c => c.callSid === 'acc_joining')).toBe(false);
    });

    it('dismisses when webhook call_id differs from SDK offer id', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'sdk_offer_99',
        wavoipOfferId: 'sdk_offer_99',
        callId: 501,
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onAccepted({
        id: 501,
        call_id: 'webhook_call_42',
        accepted_by_agent_id: 42,
        accepted_by_agent_name: 'Maria',
      });

      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE_BY'
      );
      expect(store.calls).toHaveLength(0);
    });

    it('tears down local active media when another agent claimed the call', () => {
      getActiveProviderCallId.mockReturnValue('acc_zombie');
      const store = useCallsStore();
      store.addCall({
        callSid: 'acc_zombie',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'incoming',
        provider: 'wavoip',
      });
      store.setCallActive('acc_zombie');

      wavoipVoiceCableHandlers.onAccepted({
        call_id: 'acc_zombie',
        accepted_by_agent_id: 42,
        accepted_by_agent_name: 'Maria',
      });

      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE_BY'
      );
      expect(endActiveCall).toHaveBeenCalled();
      expect(store.calls.some(c => c.callSid === 'acc_zombie')).toBe(false);
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

    it('alerts and clears inbound ring when caller hangs up before answer', () => {
      const store = useCallsStore();
      store.addCall({
        callSid: 'webhook_call_id',
        wavoipOfferId: 'sdk_offer_id',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'inbound',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onEnded({
        call_id: 'webhook_call_id',
        end_reason: 'no_answer',
        status: 'no_answer',
      });

      expect(useAlert).toHaveBeenCalledWith(
        'CONVERSATION.WAVOIP_CALL.CALLER_ENDED'
      );
      expect(store.calls).toHaveLength(0);
    });

    it('clears active inbound call when caller hangs up after answer', () => {
      getActiveProviderCallId.mockReturnValue('webhook_call_id');
      const store = useCallsStore();
      store.calls.push({
        callSid: 'webhook_call_id',
        wavoipOfferId: 'sdk_offer_id',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'inbound',
        provider: 'wavoip',
        isActive: true,
      });

      wavoipVoiceCableHandlers.onEnded({
        call_id: 'webhook_call_id',
        status: 'completed',
      });

      expect(clearActiveCall).toHaveBeenCalled();
      expect(store.calls).toHaveLength(0);
      expect(useAlert).not.toHaveBeenCalledWith(
        'CONVERSATION.WAVOIP_CALL.CALLER_ENDED'
      );
    });

    it('keeps outbound ringing call when SDK still owns the session', () => {
      isWavoipSdkCallOwned.mockImplementation(
        callId => callId === 'out_ring_001'
      );
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

    it('removes an SDK-owned outbound ghost widget after the fallback window if the SDK never confirms', () => {
      vi.useFakeTimers();
      isWavoipSdkCallOwned.mockImplementation(
        callId => callId === 'out_ghost_001'
      );
      const store = useCallsStore();
      store.addCall({
        callSid: 'out_ghost_001',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'outbound',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onEnded({
        call_id: 'out_ghost_001',
        end_reason: 'no_answer',
      });

      expect(store.calls.some(c => c.callSid === 'out_ghost_001')).toBe(true);

      vi.advanceTimersByTime(8000);

      expect(store.calls.some(c => c.callSid === 'out_ghost_001')).toBe(false);
      vi.useRealTimers();
    });

    it('does not force-remove the ghost widget fallback if the SDK already cleaned it up', () => {
      vi.useFakeTimers();
      isWavoipSdkCallOwned.mockImplementation(
        callId => callId === 'out_ghost_002'
      );
      const store = useCallsStore();
      store.addCall({
        callSid: 'out_ghost_002',
        conversationId: 1,
        inboxId: 2,
        callDirection: 'outbound',
        provider: 'wavoip',
      });

      wavoipVoiceCableHandlers.onEnded({
        call_id: 'out_ghost_002',
        end_reason: 'no_answer',
      });

      // SDK's own handler (e.g. wireOutgoingEvents' `unanswered`) removes it
      // before the fallback window elapses.
      store.removeCall('out_ghost_002');
      store.addCall({
        callSid: 'unrelated_call',
        conversationId: 2,
        inboxId: 2,
        callDirection: 'outbound',
        provider: 'wavoip',
      });

      vi.advanceTimersByTime(8000);

      expect(store.calls.some(c => c.callSid === 'out_ghost_002')).toBe(false);
      expect(store.calls.some(c => c.callSid === 'unrelated_call')).toBe(true);
      vi.useRealTimers();
    });
  });
});
