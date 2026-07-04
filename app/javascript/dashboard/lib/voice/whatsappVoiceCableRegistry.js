import { useCallsStore } from 'dashboard/stores/calls';
import {
  applyOutboundAnswer,
  armOutboundRecorder,
  handleWhatsappRemoteEnd,
  isLocalWhatsappCall,
} from 'dashboard/composables/useWhatsappCallSession';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';

export const createWhatsappVoiceCableHandlers = () => ({
  onIncoming(data) {
    const availability = window.chatwootConfig?.currentUserAvailability;
    if (availability && availability !== 'online') return;

    useCallsStore().addCall({
      callSid: data.call_id,
      callId: data.id,
      conversationId: data.conversation_id,
      inboxId: data.inbox_id,
      callDirection: VOICE_CALL_DIRECTION.INBOUND,
      provider: VOICE_CALL_PROVIDERS.WHATSAPP,
      sdpOffer: data.sdp_offer,
      iceServers: data.ice_servers,
      caller: data.caller,
    });
  },
  async onOutboundConnected(data) {
    if (!data.sdp_answer) return;
    try {
      await applyOutboundAnswer(data.id, data.sdp_answer);
    } catch (_) {
      /* noop */
    }
  },
  onOutboundAccepted(data) {
    const store = useCallsStore();
    if (!store.calls.some(c => c.callSid === data.call_id)) return;
    store.setCallActive(data.call_id);
    armOutboundRecorder();
  },
  async onEnded(data) {
    if (isLocalWhatsappCall(data.id)) {
      try {
        await handleWhatsappRemoteEnd(data.id);
      } catch (_) {
        /* noop */
      }
    }
    useCallsStore().removeCall(data.call_id);
  },
  onAccepted(data) {
    const store = useCallsStore();
    const call = store.calls.find(c => c.callSid === data.call_id);
    if (!call || call.isActive) return;
    store.dismissCall(data.call_id);
  },
  onPermissionGranted(_data, t) {
    return t
      ? t('CONVERSATION.VOICE_WIDGET.PERMISSION_GRANTED')
      : 'Contact has authorized WhatsApp calls — you can call them now.';
  },
});

export const VOICE_CALL_CABLE_HANDLERS = {
  [VOICE_CALL_PROVIDERS.WAVOIP]: 'wavoip',
  [VOICE_CALL_PROVIDERS.WHATSAPP]: 'whatsapp',
};
