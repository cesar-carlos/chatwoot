import { useStore } from 'vuex';
import { useCallsStore } from 'dashboard/stores/calls';
import CallsAPI from 'customDashboard/api/calls';
import {
  queueAcceptedByRecording,
  flushAcceptedByRecording,
  clearAcceptedByQueue,
} from 'customDashboard/lib/wavoip/wavoipAcceptRecorder';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { useWavoipOutboundCall } from 'customDashboard/composables/wavoip/useWavoipOutboundCall';
import {
  useWavoipIncomingOffer,
  removePendingOffer,
} from 'customDashboard/composables/wavoip/useWavoipIncomingOffer';
import {
  useWavoipActiveCall,
  endActiveCall as endSdkActiveCall,
  clearActiveCall as clearSdkActiveCall,
  getActiveProviderCallId,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';

export function useWavoipCallSession() {
  const store = useStore();
  const { connectForInbox, syncConnections } = useWavoipConnection();
  const { initiateOutboundCall, isInitiating } = useWavoipOutboundCall();
  const { attachToInbox, acceptOffer, rejectOffer } = useWavoipIncomingOffer();
  const { setActiveCall, clearActiveCall, setMuted, hasActiveCall } =
    useWavoipActiveCall();

  const recordAcceptedBy = async callSid => {
    const dbCallId = useCallsStore().calls.find(
      c => c.callSid === callSid
    )?.callId;
    if (!dbCallId) {
      queueAcceptedByRecording(callSid);
      return;
    }
    await CallsAPI.recordAccept(dbCallId);
  };

  const acceptIncomingCall = async ({ callId, inboxId }) => {
    await connectForInbox(inboxId);
    attachToInbox(inboxId);

    const sdkCall = await acceptOffer(callId);
    setActiveCall(sdkCall, { providerCallId: callId });
    removePendingOffer(callId);
    await recordAcceptedBy(callId);
    await flushAcceptedByRecording(callId);
    return sdkCall;
  };

  const rejectIncomingCall = async callId => {
    await rejectOffer(callId);
    useCallsStore().dismissCall(callId);
  };

  const endActiveCallSession = async callIdOverride => {
    const targetId = callIdOverride || getActiveProviderCallId();
    await endSdkActiveCall(callIdOverride);
    if (targetId) useCallsStore().removeCall(targetId);
    clearSdkActiveCall();
  };

  const cleanupSession = () => {
    clearActiveCall();
    clearAcceptedByQueue();
  };

  const connectForInboxAndListen = async inboxId => {
    await connectForInbox(inboxId);
    attachToInbox(inboxId);
  };

  const syncWithAvailability = availability => {
    syncConnections(availability);
    if (availability === 'online') {
      const inboxes = store.getters['inboxes/getInboxes'] || [];
      inboxes
        .filter(inbox => inbox.channel_type === 'Channel::Wavoip')
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
