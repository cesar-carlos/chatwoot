import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import store from 'dashboard/store';
import {
  mapCableToStoreEntry,
  findWavoipCallForCableEvent,
} from 'customDashboard/lib/voice/callStoreMappers';
import { isOutboundCallDirection } from 'customDashboard/lib/voice/voiceCallDirection';
import {
  endActiveCall as endSdkActiveCall,
  getActiveProviderCallId,
  isWavoipSdkCallOwned,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { pendingOffers } from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import { flushAcceptedByRecording } from 'customDashboard/lib/wavoip/wavoipAcceptRecorder';
import { reopenWavoipInboundConversation } from 'customDashboard/lib/wavoip/wavoipInboundConversation';
import {
  dismissWavoipCallFromStore,
  removeWavoipCallFromStore,
} from 'customDashboard/lib/wavoip/wavoipCallTeardown';
import { shouldIgnoreInboundWavoipCable } from 'customDashboard/lib/wavoip/wavoipOutboundGuard';
import { isCallDismissed } from 'dashboard/composables/useCallSession';

const currentUserId = () => store.getters.getCurrentUserID;

const alertAcceptedElsewhere = (t, agentName) => {
  useAlert(
    agentName
      ? t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE_BY', { agentName })
      : t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE')
  );
};

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
    if (
      isCallDismissed(data.call_id) ||
      (data.id != null && isCallDismissed(String(data.id)))
    ) {
      return;
    }

    const callsStore = useCallsStore();
    if (shouldIgnoreInboundWavoipCable(data, { calls: callsStore.calls })) {
      return;
    }

    const existing = findWavoipCallForCableEvent(callsStore.calls, data);

    // Escalated re-ring (timeout fallback): never re-surface a call this agent
    // already dismissed or is already handling. Backend ClaimGuard also skips
    // when claimed — this is defense in depth for late cable events.
    if (data.escalated) {
      if (
        existing?.isActive ||
        (existing?.callSid && isCallDismissed(existing.callSid)) ||
        (existing?.wavoipOfferId && isCallDismissed(existing.wavoipOfferId))
      ) {
        return;
      }
    }

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
      escalated: Boolean(data.escalated) || Boolean(existing?.escalated),
    };

    callsStore.addCall(existing ? { ...existing, ...entry } : entry);
    if (entry.conversationId) {
      reopenWavoipInboundConversation(entry.conversationId);
    }
    flushAcceptedByRecording(data.call_id, {
      t,
      onFailure: () =>
        useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPT_RECORD_FAILED')),
      onConflict: () =>
        useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE')),
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
    const callEntry = findWavoipCallForCableEvent(callsStore.calls, data);
    if (!callEntry) return;

    const acceptedBySelf =
      data.accepted_by_agent_id &&
      data.accepted_by_agent_id === currentUserId();

    const ownsLocalSession =
      callEntry.isActive ||
      (() => {
        const activeId = getActiveProviderCallId();
        return (
          activeId &&
          (activeId === data.call_id ||
            activeId === callEntry.callSid ||
            activeId === callEntry.wavoipOfferId)
        );
      })() ||
      (acceptedBySelf && isWavoipSdkCallOwned(data.call_id));

    // Same user owns this tab's SDK session — keep the live call.
    if (ownsLocalSession && acceptedBySelf) return;

    // Another agent claimed while this tab still has (or thinks it has) media.
    // Tear down so we do not keep a zombie SDK session after a failed join/PATCH.
    if (ownsLocalSession && !acceptedBySelf) {
      alertAcceptedElsewhere(t, data.accepted_by_agent_name);
      endSdkActiveCall(
        data.call_id || callEntry.callSid || callEntry.wavoipOfferId
      );
      dismissWavoipCallFromStore(
        data.call_id,
        callEntry.callSid,
        callEntry.wavoipOfferId,
        callEntry.callId
      );
      return;
    }

    // Another agent (or this user on another tab) accepted. Always dismiss the
    // ringing widget — including while this tab is mid-join — so cable-only
    // agents without SDK `acceptedElsewhere` do not keep ringing.

    // Same-user other tab: silent dismiss (no "accepted elsewhere" toast).
    // Other agent: toast even if this tab is mid-join.
    if (!acceptedBySelf) {
      alertAcceptedElsewhere(t, data.accepted_by_agent_name);
    }

    dismissWavoipCallFromStore(
      data.call_id,
      callEntry.callSid,
      callEntry.wavoipOfferId,
      callEntry.callId
    );
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
      !callEntry.isActive &&
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
      endSdkActiveCall(
        data.call_id || callEntry.callSid || callEntry.wavoipOfferId
      );
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
