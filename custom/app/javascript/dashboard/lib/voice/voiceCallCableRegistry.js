import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import conversationI18n from 'dashboard/i18n/locale/en/conversation.json';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
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

export const wavoipVoiceCableHandlers = {
  onIncoming(data) {
    const store = useCallsStore();
    store.addCall(mapCableToStoreEntry(data));
    flushAcceptedByRecording(data.call_id);

    const offerEntry = pendingOffers.get(data.call_id);
    if (offerEntry) {
      store.addCall({
        ...mapCableToStoreEntry(data),
        wavoipOfferId: offerEntry.offer.id,
      });
    }
  },
  onOutboundConnected() {},
  onOutboundAccepted(data) {
    const store = useCallsStore();
    if (!store.calls.some(c => c.callSid === data.call_id)) return;
    store.setCallActive(data.call_id);
  },
  onEnded(data) {
    const store = useCallsStore();
    const callEntry = store.calls.find(c => c.callSid === data.call_id);
    if (!callEntry) return;

    if (data.end_reason === 'handled_remotely') {
      useAlert(conversationI18n.CONVERSATION.WAVOIP_CALL.HANDLED_REMOTELY);
    }

    const isLocalOwner =
      callEntry.isActive && getActiveProviderCallId() === data.call_id;

    if (isLocalOwner) {
      endSdkActiveCall();
      clearSdkActiveCall();
    }

    removePendingOffer(data.call_id);
    store.removeCall(data.call_id);
  },
};

export const VOICE_CALL_CABLE_HANDLERS = {
  [VOICE_CALL_PROVIDERS.WAVOIP]: wavoipVoiceCableHandlers,
};
