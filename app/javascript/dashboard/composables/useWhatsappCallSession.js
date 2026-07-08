// FORK: thin wrapper over useWebRtcCallSession (WebRTC core extracted for multi-provider)
import WhatsappCallsAPI from 'dashboard/api/channel/whatsapp/whatsappCallsAPI';
import { useI18n } from 'vue-i18n';
import {
  applyOutboundAnswer,
  armOutboundRecorder,
  cleanupWebRtcSession,
  configureWebRtcCallsAPI,
  configureWebRtcTerminatePath,
  configureWebRtcTranslate,
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
  const { t } = useI18n();
  configureWebRtcTranslate(t);
  return useWebRtcCallSession();
}

export { applyOutboundAnswer, armOutboundRecorder };
