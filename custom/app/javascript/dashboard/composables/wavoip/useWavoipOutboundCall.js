import { readonly, ref } from 'vue';
import { useCallsStore } from 'dashboard/stores/calls';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { setActiveCall } from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { getWavoipClientEntry } from 'customDashboard/lib/wavoip/wavoipClientRegistry';

const isInitiating = ref(false);

const wireOutgoingEvents = call => {
  call.on?.('peerAccept', activeCall => {
    setActiveCall(activeCall, { providerCallId: call.id });
    useCallsStore().setCallActive(call.id);
  });
  call.on?.('peerReject', () => {
    useCallsStore().dismissCall(call.id);
  });
  call.on?.('unanswered', () => {
    useCallsStore().dismissCall(call.id);
  });
  call.on?.('ended', () => {
    useCallsStore().removeCall(call.id);
  });
};

export function useWavoipOutboundCall() {
  const { connectForInbox, ensureDeviceReady } = useWavoipConnection();

  const initiateOutboundCall = async (conversationId, { inboxId, toPhone }) => {
    if (isInitiating.value) return { status: 'locked' };

    isInitiating.value = true;
    try {
      const client = await connectForInbox(inboxId);
      if (!client) throw new Error('Wavoip client unavailable');

      const ready = await ensureDeviceReady(client);
      if (!ready) throw new Error('Wavoip device not ready');

      const entry = getWavoipClientEntry(inboxId);
      const fromTokens = entry?.token ? [entry.token] : undefined;
      const { call, err } = await client.startCall({
        to: toPhone,
        fromTokens,
      });

      if (err || !call) {
        throw new Error(err?.message || 'Failed to start Wavoip call');
      }

      wireOutgoingEvents(call);

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
