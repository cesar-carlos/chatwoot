import { readonly, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { useWavoipConnection } from 'customDashboard/composables/wavoip/useWavoipConnection';
import {
  setActiveCall,
  setRingingOutgoingCall,
  clearRingingOutgoingCall,
  beginOutboundInitiation,
  endOutboundInitiation,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { getWavoipClientEntry } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import { wavoipDeviceErrorKey } from 'customDashboard/lib/wavoip/wavoipDeviceReadiness';
import {
  formatWavoipStartCallError,
  formatWavoipPeerRejectError,
  unwrapWavoipSdkResult,
} from 'customDashboard/lib/wavoip/wavoipSdkResult';
import { wavoipOutboundBlockedReasonKey } from 'customDashboard/lib/wavoip/wavoipOutboundPreflight';
import {
  startWavoipOutboundRingback,
  stopWavoipOutboundRingback,
  unlockWavoipOutboundRingback,
} from 'customDashboard/lib/wavoip/wavoipOutboundRingback';
import { useCallRingtonePreference } from 'dashboard/composables/useCallRingtonePreference';

const isInitiating = ref(false);

const purgeSpuriousInboundCalls = ({
  conversationId,
  inboxId,
  keepCallSid,
}) => {
  const callsStore = useCallsStore();
  callsStore.calls
    .filter(
      call =>
        call.provider === VOICE_CALL_PROVIDERS.WAVOIP &&
        call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND &&
        call.callSid !== keepCallSid &&
        (call.conversationId === conversationId || call.inboxId === inboxId)
    )
    .forEach(call => callsStore.dismissCall(call.callSid));
};

const reopenConversationIfNeeded = async (store, conversationId) => {
  const lookup = store.getters.getConversationById;
  const conversation =
    typeof lookup === 'function' ? lookup(conversationId) : null;
  if (!conversation || conversation.status === 'open') return;

  try {
    await store.dispatch('toggleStatus', {
      conversationId,
      status: 'open',
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.debug('[Wavoip] reopen conversation on outbound failed', error);
  }
};

// The SDK call object can outlive this closure (e.g. if the client keeps its
// own reference in an active-calls list), so each terminal event unwires all
// four listeners itself instead of relying on `call` being garbage collected.
const wireOutgoingEvents = (call, inboxId, translate) => {
  setRingingOutgoingCall(call, { providerCallId: call.id, inboxId });

  const handlers = {};
  const unwire = () => {
    Object.entries(handlers).forEach(([event, handler]) =>
      call.off?.(event, handler)
    );
  };

  handlers.peerAccept = activeCall => {
    unwire();
    clearRingingOutgoingCall();
    stopWavoipOutboundRingback();
    setActiveCall(activeCall, { providerCallId: call.id, inboxId });
    useCallsStore().setCallActive(call.id);
  };
  handlers.peerReject = reason => {
    unwire();
    clearRingingOutgoingCall();
    stopWavoipOutboundRingback();
    useCallsStore().dismissCall(call.id);
    useAlert(formatWavoipPeerRejectError(reason, translate));
  };
  handlers.unanswered = () => {
    unwire();
    clearRingingOutgoingCall();
    stopWavoipOutboundRingback();
    useCallsStore().dismissCall(call.id);
  };
  handlers.ended = () => {
    unwire();
    clearRingingOutgoingCall();
    stopWavoipOutboundRingback();
    useCallsStore().removeCall(call.id);
  };

  Object.entries(handlers).forEach(([event, handler]) =>
    call.on?.(event, handler)
  );
};

export function useWavoipOutboundCall() {
  const { t } = useI18n();
  const store = useStore();
  const { connectForInbox, ensureDeviceReadiness } = useWavoipConnection();
  const { isRingtoneMuted, initPreference } = useCallRingtonePreference();

  const initiateOutboundCall = async (conversationId, { inboxId, toPhone }) => {
    if (isInitiating.value) return { status: 'locked' };

    // Fail fast with a specific, actionable message instead of letting a
    // restricted/full device reach the SDK and surface a generic error.
    const blockedReasonKey = wavoipOutboundBlockedReasonKey(inboxId);
    if (blockedReasonKey) {
      throw new Error(t(blockedReasonKey));
    }

    // Capture the click gesture before any await — FloatingCallWidget is an
    // async chunk and would otherwise be autoplay-blocked when it mounts.
    initPreference();
    unlockWavoipOutboundRingback();

    isInitiating.value = true;
    beginOutboundInitiation(inboxId, conversationId);
    try {
      let client;
      try {
        client = await connectForInbox(inboxId);
      } catch (connectError) {
        // eslint-disable-next-line no-console
        console.warn(
          '[Wavoip] connect failed before starting call',
          connectError
        );
        throw new Error(t('CONVERSATION.WAVOIP_CALL.CONNECT_FAILED'));
      }
      if (!client) {
        throw new Error(t('CONVERSATION.WAVOIP_CALL.CLIENT_UNAVAILABLE'));
      }

      const { ready, status } = await ensureDeviceReadiness(client, inboxId);
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

      wireOutgoingEvents(call, inboxId, t);

      const providerCallId = call.id;
      useCallsStore().addCall({
        callSid: providerCallId,
        conversationId,
        inboxId,
        callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
        provider: VOICE_CALL_PROVIDERS.WAVOIP,
      });
      if (!isRingtoneMuted.value) {
        startWavoipOutboundRingback();
      }
      purgeSpuriousInboundCalls({
        conversationId,
        inboxId,
        keepCallSid: providerCallId,
      });
      await reopenConversationIfNeeded(store, conversationId);

      return {
        id: null,
        call_id: providerCallId,
        status: 'started',
      };
    } catch (error) {
      stopWavoipOutboundRingback();
      throw error;
    } finally {
      endOutboundInitiation();
      isInitiating.value = false;
    }
  };

  return {
    isInitiating: readonly(isInitiating),
    initiateOutboundCall,
  };
}
