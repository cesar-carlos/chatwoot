import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import {
  applyOutboundAnswer,
  armOutboundRecorder,
  cleanupWebRtcSession,
  configureWebRtcCallsAPI,
  configureWebRtcTerminatePath,
  handleWebRtcRemoteEnd,
  hasActiveWebRtcCall,
  isLocalWebRtcCall,
  sendWebRtcTerminateBeacon,
  setWebRtcCallMuted,
  useWebRtcCallSession,
} from './useWebRtcCallSession';

configureWebRtcCallsAPI(WhatsappCallsAPI);
configureWebRtcTerminatePath(
  (accountId, callId) =>
    `/api/v1/accounts/${accountId}/whatsapp_calls/${callId}/terminate`
);

export const hasActiveWhatsappCall = hasActiveWebRtcCall;
export const isLocalWhatsappCall = isLocalWebRtcCall;
export const cleanupWhatsappSession = cleanupWebRtcSession;
export const handleWhatsappRemoteEnd = handleWebRtcRemoteEnd;
export const setWhatsappCallMuted = setWebRtcCallMuted;
export const sendWhatsappTerminateBeacon = sendWebRtcTerminateBeacon;

export function useWhatsappCallSession() {
  const prepareInboundAnswer = async (sdpOffer, iceServers) => {
    cleanup();
    localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    buildPeerConnection(iceServers);
    localStream.getTracks().forEach(t => pc.addTrack(t, localStream));
    await pc.setRemoteDescription({ type: 'offer', sdp: sdpOffer });
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await waitForIceGatheringComplete(pc);
    return pc.localDescription.sdp;
  };

  const prepareOutboundOffer = async () => {
    cleanup();
    localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    buildPeerConnection(DEFAULT_OUTBOUND_ICE_SERVERS);
    localStream.getTracks().forEach(t => pc.addTrack(t, localStream));
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await waitForIceGatheringComplete(pc);
    return pc.localDescription.sdp;
  };

  const acceptIncomingCall = async ({ callId, sdpOffer, iceServers }) => {
    // The store may not have sdpOffer yet (the cable broadcast can race the
    // click). Fall back to GET /whatsapp_calls/:id which exposes it.
    let offer = sdpOffer;
    let ice = iceServers;
    if (!offer && callId) {
      try {
        const fresh = await WhatsappCallsAPI.show(callId);
        offer = fresh?.sdp_offer || fresh?.sdpOffer;
        ice = ice || fresh?.ice_servers || fresh?.iceServers;
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error(
          '[WhatsApp Call] failed to fetch call data for accept:',
          e
        );
      }
    }
    if (!offer) {
      throw new Error('Missing sdp_offer for accept — call may have ended.');
    }

    // Release the mic + peer connection if anything between here and the accept
    // round-trip fails — otherwise a rejected accept leaves the mic live and
    // activeCallId set. Mirrors rejectIncomingCall's self-cleanup; rethrow so
    // the caller can surface the failure and skip marking the call active.
    try {
      const sdpAnswer = await prepareInboundAnswer(offer, ice);
      activeCallId = callId;
      // Inbound: agent's click is the pickup. Arm the recorder before the API
      // round-trip so when ontrack fires (triggered by setRemoteDescription
      // back in prepareInboundAnswer) the recorder is already authorized.
      recorderArmed = true;
      setupRecorder();
      await WhatsappCallsAPI.accept(callId, sdpAnswer);
    } catch (e) {
      cleanup();
      throw e;
    }
  };

  const rejectIncomingCall = async callId => {
    try {
      await WhatsappCallsAPI.reject(callId);
    } finally {
      cleanup();
    }
  };

  // target: { conversationId } or { contactId, inboxId }
  const initiateOutboundCall = async target => {
    // Module-scoped lock + active-session guard so a second click — from the
    // same composable instance OR a different one (header vs contact panel)
    // OR while a call is already live — can't tear down the in-flight setup
    // via prepareOutboundOffer's cleanup().
    if (isInitiatingOutbound.value)
      return { status: VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED };
    if (hasActiveWhatsappCall())
      return { status: VOICE_CALL_OUTBOUND_INIT_STATUS.LOCKED };
    isInitiatingOutbound.value = true;
    try {
      const sdpOffer = await prepareOutboundOffer();
      const response = await WhatsappCallsAPI.initiate(target, sdpOffer);
      if (response?.id) {
        activeCallId = response.id;
        // A connect webhook that raced ahead of this response was buffered;
        // apply our own by id now that we know it, then drop every buffered
        // answer (concurrent agents' calls aren't ours to apply).
        const buffered = pendingOutboundAnswers.get(activeCallId);
        pendingOutboundAnswers.clear();
        if (buffered) {
          await pc.setRemoteDescription({
            type: 'answer',
            sdp: buffered,
          });
        }
        return response;
      }
      // No call id back: this is the permission-request branch. The mic +
      // PeerConnection allocated by prepareOutboundOffer aren't useful until
      // the contact opts in and the agent retries — release them.
      cleanup();
      return response;
    } catch (e) {
      cleanup();
      // BE returns 422 when the contact hasn't opted in (permission template
      // sent or already pending). Surface it to the caller as a normal
      // response shape so it can render the banner instead of an error toast.
      const data = e?.response?.data;
      if (
        data?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_REQUESTED ||
        data?.status === VOICE_CALL_OUTBOUND_INIT_STATUS.PERMISSION_PENDING
      ) {
        return { status: data.status, conversation_id: data.conversation_id };
      }
      throw e;
    } finally {
      isInitiatingOutbound.value = false;
    }
  };

  // callIdOverride is the call.id from the dashboard's calls store. Module
  // `activeCallId` may be null after a prior accept attempt's cleanup() — but
  // the call still exists on Meta and must still be terminated. Falling back
  // to the override means hangup is robust to a wiped local session.
  const endActiveCall = async (callIdOverride = null) => {
    const callId = activeCallId || callIdOverride;
    if (!callId) {
      cleanup();
      return;
    }
    try {
      // Terminate on Meta first so the contact is disconnected immediately. The
      // recording upload below can be slow on long calls or poor networks, and
      // the peer connection / mic must not stay live for the contact during it.
      await WhatsappCallsAPI.terminate(callId).catch(() => {});
      await stopRecorderAndUpload(callId);
    } finally {
      cleanup();
    }
  };

  return {
    isInitiating: isInitiatingOutboundReadonly,
    prepareInboundAnswer,
    prepareOutboundOffer,
    acceptIncomingCall,
    rejectIncomingCall,
    initiateOutboundCall,
    endActiveCall,
  };
}

export {
  applyOutboundAnswer,
  armOutboundRecorder,
};
