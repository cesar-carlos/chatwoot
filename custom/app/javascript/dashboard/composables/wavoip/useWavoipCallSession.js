import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import {
  queueAcceptedByRecording,
  flushAcceptedByRecording,
  clearAcceptedByQueue,
  recordAcceptWithRetry,
  recordJoinWithRetry,
} from 'customDashboard/lib/wavoip/wavoipAcceptRecorder';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { shouldAgentReceiveWavoipCalls } from 'customDashboard/lib/wavoip/wavoipInboxCallRouting';
import { useWavoipOutboundCall } from 'customDashboard/composables/wavoip/useWavoipOutboundCall';
import {
  useWavoipIncomingOffer,
  removePendingOffer,
  waitForPendingOffer,
  getPendingOffer,
} from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import {
  useWavoipActiveCall,
  endActiveCall as endSdkActiveCall,
  clearRingingOutgoingCall,
  clearActiveCall,
  getActiveProviderCallId,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { closeIncomingWavoipOfferNotification } from 'customDashboard/composables/wavoip/useWavoipNotifications';

const closeOfferNotificationsForCall = (callSid, call) => {
  closeIncomingWavoipOfferNotification(callSid);
  if (call?.wavoipOfferId) {
    closeIncomingWavoipOfferNotification(call.wavoipOfferId);
  }
};

export function useWavoipCallSession() {
  const store = useStore();
  const { t } = useI18n();
  const { connectForInbox, syncConnections } = useWavoipConnection();
  const { initiateOutboundCall, isInitiating } = useWavoipOutboundCall();
  const { attachToInbox, acceptOffer, rejectOffer } = useWavoipIncomingOffer();
  const { setActiveCall, setMuted, hasActiveCall } = useWavoipActiveCall();

  const acceptRecordFailure = () => {
    useAlert(t('CONVERSATION.WAVOIP_CALL.ACCEPT_RECORD_FAILED'));
  };

  const recordAcceptedBy = async callSid => {
    const dbCallId = useCallsStore().calls.find(
      c => c.callSid === callSid
    )?.callId;
    if (!dbCallId) {
      queueAcceptedByRecording(callSid);
      return;
    }
    await recordJoinWithRetry(dbCallId, callSid, {
      onFailure: acceptRecordFailure,
    });
    await recordAcceptWithRetry(dbCallId, callSid, {
      onFailure: acceptRecordFailure,
    });
  };

  const acceptIncomingCall = async ({ callId, inboxId }) => {
    await connectForInbox(inboxId);
    attachToInbox(inboxId);

    if (!getPendingOffer(callId)) {
      await waitForPendingOffer(callId);
    }

    const callsStore = useCallsStore();
    const storeCall = callsStore.calls.find(
      c => c.callSid === callId || c.wavoipOfferId === callId
    );

    const sdkCall = await acceptOffer(callId);
    // Accepting agent: drop the OS notification immediately so it does not
    // linger while the call is already live in this tab.
    closeOfferNotificationsForCall(callId, storeCall);
    setActiveCall(sdkCall, { providerCallId: callId, inboxId });
    removePendingOffer(callId);
    await recordAcceptedBy(callId);
    await flushAcceptedByRecording(callId, { onFailure: acceptRecordFailure });
    return sdkCall;
  };

  const rejectIncomingCall = async callId => {
    const callsStore = useCallsStore();
    const storeCall = callsStore.calls.find(
      c => c.callSid === callId || c.wavoipOfferId === callId
    );
    closeOfferNotificationsForCall(callId, storeCall);
    await rejectOffer(callId);
    callsStore.dismissCall(callId);
  };

  const endActiveCallSession = async callIdOverride => {
    const targetId = callIdOverride || getActiveProviderCallId();
    await endSdkActiveCall(callIdOverride);
    if (targetId) useCallsStore().removeCall(targetId);
  };

  const cleanupSession = () => {
    clearActiveCall();
    clearRingingOutgoingCall();
    clearAcceptedByQueue();
  };

  const connectForInboxAndListen = async inboxId => {
    await connectForInbox(inboxId);
    attachToInbox(inboxId);
  };

  const syncWithAvailability = async availability => {
    await syncConnections(availability);
    if (availability === 'online') {
      const inboxes = store.getters['inboxes/getInboxes'] || [];
      const isAdministrator = store.getters.getCurrentRole === 'administrator';
      inboxes
        .filter(
          inbox =>
            inbox.channel_type === INBOX_TYPES.WAVOIP &&
            shouldAgentReceiveWavoipCalls(inbox, { isAdministrator })
        )
        .forEach(inbox => attachToInbox(inbox.id));
    }
  };

  return {
    isInitiating,
    connectForInbox: connectForInboxAndListen,
    syncWithAvailability,
    initiateOutboundCall,
    acceptIncomingCall,
    rejectIncomingCall,
    endActiveCall: endActiveCallSession,
    setMuted,
    cleanupSession,
    hasActiveCall,
  };
}
