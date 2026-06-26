import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import store from 'dashboard/store';
import { mapCableToStoreEntry } from 'customDashboard/lib/voice/callStoreMappers';
import {
  endActiveCall as endSdkActiveCall,
  clearActiveCall as clearSdkActiveCall,
  getActiveProviderCallId,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import {
  removePendingOffer,
  pendingOffers,
} from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import { flushAcceptedByRecording } from 'customDashboard/lib/wavoip/wavoipAcceptRecorder';
import { isCallJoining, isCallDismissed } from 'dashboard/composables/useCallSession';

const currentUserId = () => store.getters.getCurrentUserID;

export const createWavoipVoiceCableHandlers = t => ({
  onIncoming(data) {
    if (isCallDismissed(data.call_id)) return;

    const callsStore = useCallsStore();
    const existing = callsStore.calls.find(c => c.callSid === data.call_id);
    const offerEntry = pendingOffers.get(data.call_id);

    const entry = {
      ...mapCableToStoreEntry(data),
      awaitingSdkOffer: !offerEntry,
      wavoipOfferId: offerEntry?.offer?.id || data.call_id,
    };

    callsStore.addCall(existing ? { ...existing, ...entry } : entry);
    flushAcceptedByRecording(data.call_id);
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

    useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPTED_ELSEWHERE'));
    removePendingOffer(data.call_id);
    callsStore.dismissCall(data.call_id);
  },
  onEnded(data) {
    const callsStore = useCallsStore();
    const callEntry = callsStore.calls.find(c => c.callSid === data.call_id);
    if (!callEntry) return;

    if (data.end_reason === 'handled_remotely') {
      useAlert(t('CONVERSATION.WAVOIP_CALL.HANDLED_REMOTELY'));
    }

    const isLocalOwner =
      callEntry.isActive && getActiveProviderCallId() === data.call_id;

    if (isLocalOwner) {
      endSdkActiveCall();
      clearSdkActiveCall();
    }

    removePendingOffer(data.call_id);
    callsStore.removeCall(data.call_id);
  },
});
