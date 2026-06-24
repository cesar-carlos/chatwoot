import { readonly, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCallsStore } from 'dashboard/stores/calls';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import {
  setActiveCall,
  setRingingOutgoingCall,
  clearRingingOutgoingCall,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { getWavoipClientEntry } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { wavoipDeviceErrorKey } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import {
  formatWavoipStartCallError,
  unwrapWavoipSdkResult,
} from 'customDashboard/lib/wavoip/wavoipSdkResult';
import { wireCallDiagnostics } from 'customDashboard/lib/wavoip/wavoipCallDiagnostics';

const isInitiating = ref(false);

const wireOutgoingEvents = (call, inboxId) => {
  setRingingOutgoingCall(call, { providerCallId: call.id, inboxId });
  wireCallDiagnostics(call, { inboxId, callId: call.id });

  call.on?.('peerAccept', activeCall => {
    clearRingingOutgoingCall();
    setActiveCall(activeCall, { providerCallId: call.id, inboxId });
    useCallsStore().setCallActive(call.id);
  });
  call.on?.('peerReject', () => {
    clearRingingOutgoingCall();
    useCallsStore().dismissCall(call.id);
  });
  call.on?.('unanswered', () => {
    clearRingingOutgoingCall();
    useCallsStore().dismissCall(call.id);
  });
  call.on?.('ended', () => {
    clearRingingOutgoingCall();
    useCallsStore().removeCall(call.id);
  });
};

export function useWavoipOutboundCall() {
  const { t } = useI18n();
  const { connectForInbox, ensureDeviceReadiness } = useWavoipConnection();

  const initiateOutboundCall = async (conversationId, { inboxId, toPhone }) => {
    if (isInitiating.value) return { status: 'locked' };

    isInitiating.value = true;
    try {
      const client = await connectForInbox(inboxId);
      if (!client) {
        throw new Error(t('CONVERSATION.WAVOIP_CALL.CLIENT_UNAVAILABLE'));
      }

      const { ready, status } = await ensureDeviceReadiness(client);
      if (!ready) {
        // eslint-disable-next-line no-console
        console.warn('[Wavoip] device not ready', { inboxId, status });
        throw new Error(t(wavoipDeviceErrorKey(status)));
      }

      const entry = getWavoipClientEntry(inboxId);
      const fromTokens = entry?.token ? [entry.token] : undefined;
      const result = await client.startCall({
        to: toPhone,
        fromTokens,
      });
      const { call, err } = unwrapWavoipSdkResult(result);

      if (err || !call) {
        throw new Error(formatWavoipStartCallError(err, t));
      }

      wireOutgoingEvents(call, inboxId);

      const providerCallId = call.id;
      useCallsStore().addCall({
        callSid: providerCallId,
        conversationId,
        inboxId,
        callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
      });

      return {
        id: null,
        call_id: providerCallId,
        status: 'started',
      };
    } finally {
      isInitiating.value = false;
    }
  };

  return {
    isInitiating: readonly(isInitiating),
    initiateOutboundCall,
  };
}
