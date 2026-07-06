import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import store from 'dashboard/store';
import {
  mapCableToStoreEntry,
  findWavoipCallForCableEvent,
} from 'customDashboard/lib/voice/callStoreMappers';
import { isOutboundCallDirection } from 'customDashboard/lib/voice/voiceCallDirection';
import {
  clearActiveCall as clearSdkActiveCall,
  getActiveProviderCallId,
  isWavoipSdkCallOwned,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import {
  removePendingOffer,
  pendingOffers,
} from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import { flushAcceptedByRecording } from 'customDashboard/lib/wavoip/wavoipAcceptRecorder';
import { reopenWavoipInboundConversation } from 'customDashboard/lib/wavoip/wavoipInboundConversation';
import { removeWavoipCallFromStore } from 'customDashboard/lib/wavoip/wavoipCallTeardown';
import { shouldIgnoreInboundWavoipCable } from 'customDashboard/lib/wavoip/wavoipOutboundGuard';
import {
  isCallJoining,
  isCallDismissed,
} from 'dashboard/composables/useCallSession';

const currentUserId = () => store.getters.getCurrentUserID;

// The SDK is treated as the source of truth for an outbound ringing widget
// (see GAP-OUTBOUND-01 in the Wavoip changelog): the webhook can report a
// terminal status before the SDK's own peerAccept/peerReject/unanswered
// fires, and removing the widget right away would make it disappear while
// the callee's phone is still actually ringing. But if the SDK's own event
// never arrives (dropped network event, backgrounded tab, SDK bug), that
// call would ring forever with no way to end it from the UI. This schedules
// a bounded fallback removal so the widget can't become a permanent ghost —
// it's a no-op if the SDK's own handler already removed the call by then.
const GHOST_WIDGET_FALLBACK_MS = 8000;

const scheduleGhostWidgetFallback = (callId, callEntry) => {
  setTimeout(() => {
    const callsStore = useCallsStore();
    const stillPresent = callsStore.calls.find(
      c =>
        c.callSid === callEntry.callSid ||
        (callEntry.wavoipOfferId && c.wavoipOfferId === callEntry.wavoipOfferId)
    );
    if (!stillPresent || stillPresent.isActive) return;

    removeWavoipCallFromStore(
      callId,
      stillPresent.callSid,
      stillPresent.wavoipOfferId
    );
  }, GHOST_WIDGET_FALLBACK_MS);
};

export const createWavoipVoiceCableHandlers = t => ({
  onIncoming(data) {
    if (isCallDismissed(data.call_id)) return;

    const callsStore = useCallsStore();
    if (shouldIgnoreInboundWavoipCable(data, { calls: callsStore.calls })) {
      return;
    }

    const existing = findWavoipCallForCableEvent(callsStore.calls, data);
    const offerEntry =
      pendingOffers.get(data.call_id) ||
      (existing?.wavoipOfferId && pendingOffers.get(existing.wavoipOfferId));

    const mapped = mapCableToStoreEntry(data);
    const entry = {
      ...mapped,
      // Keep the SDK-origin callSid as canonical when this cable event
      // reconciles onto a row the offer already created under its own id.
      callSid: existing?.callSid || mapped.callSid,
      awaitingSdkOffer: !offerEntry,
      wavoipOfferId:
        offerEntry?.offer?.id || existing?.wavoipOfferId || data.call_id,
    };

    callsStore.addCall(existing ? { ...existing, ...entry } : entry);
    if (entry.conversationId) {
      reopenWavoipInboundConversation(entry.conversationId);
    }
    flushAcceptedByRecording(data.call_id, {
      t,
      onFailure: () =>
        useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPT_RECORD_FAILED')),
    });
  },
  onOutboundAccepted(data) {
    const callsStore = useCallsStore();
    const callEntry = callsStore.calls.find(c => c.callSid === data.call_id);
    if (!callEntry) return;
    // Media is owned by peerAccept; cable only syncs UI when SDK session exists.
    if (getActiveProviderCallId() === data.call_id) {
      callsStore.setCallActive(data.call_id);
    }
  },
  onAccepted(data) {
    const callsStore = useCallsStore();
    const callEntry = callsStore.calls.find(c => c.callSid === data.call_id);
    if (!callEntry) return;

    if (callEntry.isActive) return;
    if (isCallJoining()) return;
    if (getActiveProviderCallId() === data.call_id) return;
    if (
      data.accepted_by_agent_id &&
      data.accepted_by_agent_id === currentUserId()
    ) {
      return;
    }

    const agentName = data.accepted_by_agent_name;

    useAlert(
      agentName
        ? t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE_BY', { agentName })
        : t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE')
    );
    removePendingOffer(data.call_id);
    callsStore.dismissCall(data.call_id);
  },
  onEnded(data) {
    const callsStore = useCallsStore();
    const callEntry = callsStore.calls.find(
      c => c.callSid === data.call_id || c.wavoipOfferId === data.call_id
    );
    if (!callEntry) return;

    if (data.end_reason === 'handled_remotely') {
      useAlert(t('CONVERSATION.WAVOIP_CALL.HANDLED_REMOTELY'));
    } else if (
      !isOutboundCallDirection(callEntry.callDirection) &&
      (data.end_reason === 'no_answer' ||
        data.status === 'no_answer' ||
        data.status === 'missed' ||
        data.status === 'completed')
    ) {
      useAlert(t('CONVERSATION.WAVOIP_CALL.CALLER_ENDED'));
    }

    const ownsActiveSession =
      callEntry.isActive &&
      (getActiveProviderCallId() === data.call_id ||
        getActiveProviderCallId() === callEntry.callSid ||
        getActiveProviderCallId() === callEntry.wavoipOfferId ||
        isWavoipSdkCallOwned(data.call_id) ||
        isWavoipSdkCallOwned(callEntry.callSid) ||
        isWavoipSdkCallOwned(callEntry.wavoipOfferId));

    if (ownsActiveSession) {
      clearSdkActiveCall();
    }

    if (
      isOutboundCallDirection(callEntry.callDirection) &&
      !callEntry.isActive &&
      isWavoipSdkCallOwned(data.call_id)
    ) {
      scheduleGhostWidgetFallback(data.call_id, callEntry);
      return;
    }

    removeWavoipCallFromStore(
      data.call_id,
      callEntry.callSid,
      callEntry.wavoipOfferId
    );
  },
});
