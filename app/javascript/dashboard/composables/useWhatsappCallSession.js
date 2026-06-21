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
  return useWebRtcCallSession();
}

export { applyOutboundAnswer, armOutboundRecorder };
