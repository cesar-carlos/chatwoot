import { computed, readonly, ref, watch, onUnmounted, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import VoiceAPI from 'dashboard/api/channel/voice/voiceAPIClient';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { useCallsStore } from 'dashboard/stores/calls';
import { useAlert } from 'dashboard/composables';
import {
  useWhatsappCallSession,
  sendWhatsappTerminateBeacon,
} from 'dashboard/composables/useWhatsappCallSession';
import { markLocalCall, clearLocalCall } from 'dashboard/helper/voice';
import { markCallDismissed } from 'dashboard/helper/voiceCallDismissed';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { isBrowserVoiceProvider } from 'customDashboard/lib/voice/browserVoiceProviders';
// FORK: Wavoip voice session registry (factory wired in Phase 2)
import {
  getBrowserVoiceSession,
  isWavoipVoiceCall,
  isWhatsappVoiceCall,
  shouldRejectWavoipInboundOnDismiss,
  cleanupAfterBrowserVoiceJoinFailure,
} from 'customDashboard/lib/voice/voiceSessionRegistry';
import {
  seedVoiceCallsFromHydratedMessages as seedVoiceCallsFromHydratedMessagesHelper,
  resetSeedVoiceCallsFingerprints,
} from 'customDashboard/lib/voice/seedVoiceCallsFromHydratedMessages';
import { addToCappedSet } from 'customDashboard/lib/voice/cappedSet';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import Timer from 'dashboard/helper/Timer';

const isBrowserVoiceCall = call => isBrowserVoiceProvider(call?.provider);

const resolveBrowserVoiceSession = (
  call,
  { whatsappSession, browserVoiceSessionFor }
) => {
  if (isWhatsappVoiceCall(call)) return whatsappSession;
  if (isWavoipVoiceCall(call)) {
    return browserVoiceSessionFor(VOICE_CALL_PROVIDERS.WAVOIP);
  }
  return null;
};

const ringtoneSilencedCallSids = new Set();
export const isCallRingtoneSilenced = callSid =>
  callSid ? ringtoneSilencedCallSids.has(callSid) : false;
const silenceCallRingtone = (callSid, call) => {
  addToCappedSet(ringtoneSilencedCallSids, callSid);
  // Also silence by wavoipOfferId so aliased entries are covered.
  addToCappedSet(ringtoneSilencedCallSids, call?.wavoipOfferId);
};

// Globals attached once across all useCallSession() consumers — bubbles in a
// long thread call this composable many times, and a per-instance Timer +
// window listener stack would multiply work.
let globalsAttachedCount = 0;
let globalDurationTimer = null;
const globalCallDuration = ref(0);
let storedCallsStoreRef = null;
// Shared join lock so two surfaces (bubble + widget) clicking concurrently
// see one in-flight join, not two unrelated isJoining refs.
const globalIsJoining = ref(false);
const globalIsJoiningReadonly = readonly(globalIsJoining);
const SEED_CALLS_DEBOUNCE_MS = 200;
let seedCallsDebounceTimer = null;
let seedCallsFromHydratedMessagesFn = null;

export const isCallJoining = () => globalIsJoining.value;

const handleBeforeUnloadGlobal = event => {
  const store = storedCallsStoreRef;
  if (!store) return;
  if (!store.hasActiveCall && !store.hasIncomingCall) return;
  event.preventDefault();
  event.returnValue = '';
};
const handlePageHideGlobal = () => {
  sendWhatsappTerminateBeacon();

  const store = storedCallsStoreRef;
  const active = store?.activeCall;
  // FORK: tear down Wavoip session on page hide
  if (active?.provider === VOICE_CALL_PROVIDERS.WAVOIP) {
    const session = getBrowserVoiceSession(VOICE_CALL_PROVIDERS.WAVOIP);
    session?.endActiveCall?.(active.callSid);
  }
};
const handleTwilioDisconnectedGlobal = () =>
  storedCallsStoreRef?.clearActiveCall();

const attachGlobalsOnFirstMount = callsStore => {
  globalsAttachedCount += 1;
  if (globalsAttachedCount > 1) return;
  storedCallsStoreRef = callsStore;
  globalDurationTimer = new Timer(elapsed => {
    globalCallDuration.value = elapsed;
  });
  TwilioVoiceClient.addEventListener(
    'call:disconnected',
    handleTwilioDisconnectedGlobal
  );
  window.addEventListener('beforeunload', handleBeforeUnloadGlobal);
  window.addEventListener('pagehide', handlePageHideGlobal);
};

const clearSeedCallsDebounce = () => {
  if (!seedCallsDebounceTimer) return;
  clearTimeout(seedCallsDebounceTimer);
  seedCallsDebounceTimer = null;
};

const scheduleSeedCallsFromHydratedMessages = () => {
  if (!seedCallsFromHydratedMessagesFn) return;
  clearSeedCallsDebounce();
  seedCallsDebounceTimer = setTimeout(() => {
    seedCallsDebounceTimer = null;
    seedCallsFromHydratedMessagesFn();
  }, SEED_CALLS_DEBOUNCE_MS);
};

const detachGlobalsOnLastUnmount = () => {
  globalsAttachedCount -= 1;
  if (globalsAttachedCount > 0) return;
  clearSeedCallsDebounce();
  globalDurationTimer?.stop();
  globalDurationTimer = null;
  globalCallDuration.value = 0;
  storedCallsStoreRef = null;
  // FORK: drop hydrated voice-call seed fingerprints with the session
  resetSeedVoiceCallsFingerprints();
  TwilioVoiceClient.removeEventListener(
    'call:disconnected',
    handleTwilioDisconnectedGlobal
  );
  window.removeEventListener('beforeunload', handleBeforeUnloadGlobal);
  window.removeEventListener('pagehide', handlePageHideGlobal);
};

// Build the action surface used by both the root session composable and the
// lighter useCallActions consumer. All state is module-scoped — the actions
// don't depend on per-instance refs, so they're cheap to call from anywhere.
const buildCallActions = ({
  callsStore,
  whatsappSession,
  t,
  browserVoiceSessionFor = getBrowserVoiceSession,
}) => {
  const findCall = callSid => callsStore.calls.find(c => c.callSid === callSid);

  const endCall = async ({ conversationId, inboxId, callSid }) => {
    const call = findCall(callSid);
    const browserSession = resolveBrowserVoiceSession(call, {
      whatsappSession,
      browserVoiceSessionFor,
    });

    if (browserSession?.endActiveCall) {
      // WhatsApp: pass call.callId so a wiped module state still hits /terminate.
      // Wavoip: pass callSid (SDK / store key).
      const endId = isWhatsappVoiceCall(call) ? call?.callId : call?.callSid;
      await browserSession.endActiveCall(endId);
      globalDurationTimer?.stop();
      if (isWhatsappVoiceCall(call)) callsStore.clearActiveCall();
      return;
    }

    // try/finally so a failed leaveConference (e.g. backend 5xx) still
    // tears down the local Device and UI state — otherwise the call stays
    // visually active with the mic open.
    try {
      await VoiceAPI.leaveConference({ inboxId, conversationId, callSid });
    } finally {
      TwilioVoiceClient.endClientCall();
      globalDurationTimer?.stop();
      callsStore.clearActiveCall();
      clearLocalCall(callSid);
    }
  };

  const joinCall = async ({ conversationId, inboxId, callSid }) => {
    if (globalIsJoining.value) return null;

    const call = findCall(callSid);
    // Outbound *WhatsApp* calls have no separate join step — the offer was
    // sent at initiate time and the answer is applied by the cable handler.
    // Routing through acceptIncomingCall here would call prepareInboundAnswer →
    // cleanup() and destroy the live outbound session. Outbound *Twilio*
    // calls still need joinConference + joinClientCall (FloatingCallWidget
    // auto-joins them), so don't short-circuit those.
    if (
      call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND &&
      isBrowserVoiceCall(call)
    ) {
      return null;
    }

    globalIsJoining.value = true;
    try {
      const browserSession = resolveBrowserVoiceSession(call, {
        whatsappSession,
        browserVoiceSessionFor,
      });

      if (isWavoipVoiceCall(call)) {
        // FORK: missing session before SDK accept
        if (!browserSession?.acceptIncomingCall) {
          useAlert(t('CONVERSATION.WAVOIP_CALL.CLIENT_UNAVAILABLE'));
          return null;
        }
      }

      if (browserSession?.acceptIncomingCall) {
        if (isWhatsappVoiceCall(call)) {
          await browserSession.acceptIncomingCall({
            callId: call.callId,
            sdpOffer: call.sdpOffer,
            iceServers: call.iceServers,
          });
        } else {
          await browserSession.acceptIncomingCall({
            callId: call.callSid,
            inboxId: call.inboxId,
            conversationId: call.conversationId,
          });
        }
        callsStore.setCallActive(callSid);
        globalDurationTimer?.start();
        return { callId: call.callId };
      }

      const device = await TwilioVoiceClient.initializeDevice(inboxId);
      if (!device) return null;

      // Set BEFORE the join call lands so the account-wide voice_call.accepted
      // broadcast — which can arrive back at this same tab before this await
      // resolves — recognizes this as its own call instead of tearing it down
      // (mirrors useWhatsappCallSession's activeCallId).
      markLocalCall(callSid);

      const joinResponse = await VoiceAPI.joinConference({
        conversationId,
        inboxId,
        callSid,
      });

      await TwilioVoiceClient.joinClientCall({
        to: joinResponse?.conference_sid,
        conversationId,
        callSid,
      });

      callsStore.setCallActive(callSid);
      globalDurationTimer?.start();

      return { conferenceSid: joinResponse?.conference_sid };
    } catch (error) {
      const alertMessage = error?.i18nKey
        ? t(error.i18nKey)
        : error?.response?.data?.error || t('CONTACT_PANEL.CALL_FAILED');
      useAlert(alertMessage);
      if (!isWhatsappVoiceCall(call) && !isWavoipVoiceCall(call)) {
        clearLocalCall(callSid);
      }
      // 409 = the call already ended before accept landed (e.g. caller hung up mid-ring).
      if (error?.response?.status === 409) {
        TwilioVoiceClient.endClientCall();
        markCallDismissed(callSid);
        callsStore.dismissCall(callSid);
      } else if (!isWhatsappVoiceCall(call) && !isWavoipVoiceCall(call)) {
        // Tear down the Twilio Device on any other join error so a retry
        // starts from a clean state — joinClientCall can leave the device
        // half-initialized after a network blip.
        TwilioVoiceClient.endClientCall();
      }
      // eslint-disable-next-line no-console
      console.error('Failed to join call:', error);
      if (cleanupAfterBrowserVoiceJoinFailure(call, callSid)) {
        markCallDismissed(callSid);
        callsStore.dismissCall(callSid);
      }
      return null;
    } finally {
      globalIsJoining.value = false;
    }
  };

  // Await provider-side reject before dismissing the local entry; if the API
  // call fails the call should stay surfaced so the agent can retry instead of
  // disappearing while the backend still rings.
  const rejectIncomingCall = async callSid => {
    const call = findCall(callSid);
    // Silence the ringtone for this agent immediately — before the async SDK
    // reject so there's no audible gap while the provider round-trips.
    silenceCallRingtone(callSid, call);
    try {
      const browserSession = resolveBrowserVoiceSession(call, {
        whatsappSession,
        browserVoiceSessionFor,
      });

      if (browserSession) {
        if (call.callDirection === VOICE_CALL_DIRECTION.OUTBOUND) {
          // Outbound still ringing: terminate, don't reject (inbound verb).
          const endId = isWhatsappVoiceCall(call) ? call.callId : undefined;
          await browserSession.endActiveCall?.(endId);
        } else if (isWhatsappVoiceCall(call) && call?.callId) {
          await browserSession.rejectIncomingCall(call.callId);
        } else if (isWavoipVoiceCall(call)) {
          // FORK: reject/dismiss Wavoip call via SDK session
          await browserSession.rejectIncomingCall?.(call.callSid);
        }
      } else if (call?.inboxId && call?.conversationId) {
        // Twilio incoming reject: agent hasn't joined the Device yet, so
        // endClientCall is a no-op. End the conference server-side instead
        // so Twilio hangs up the inbound leg.
        await VoiceAPI.leaveConference({
          inboxId: call.inboxId,
          conversationId: call.conversationId,
          callSid,
        });
      } else {
        TwilioVoiceClient.endClientCall();
      }
    } finally {
      markCallDismissed(callSid);
      callsStore.dismissCall(callSid);
    }
  };

  const dismissCall = async callSid => {
    const call = findCall(callSid);
    silenceCallRingtone(callSid, call);
    // FORK: dismiss inbound Wavoip rings via SDK reject
    if (shouldRejectWavoipInboundOnDismiss(call)) {
      await rejectIncomingCall(callSid);
      return;
    }
    markCallDismissed(callSid);
    callsStore.dismissCall(callSid);
  };

  return { endCall, joinCall, rejectIncomingCall, dismissCall };
};

const buildReactiveSurface = callsStore => {
  const activeCall = computed(() => callsStore.activeCall);
  const incomingCalls = computed(() => callsStore.incomingCalls);
  const hasActiveCall = computed(() => callsStore.hasActiveCall);
  const formattedCallDuration = computed(() => {
    const total = globalCallDuration.value;
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  });
  return {
    activeCall,
    incomingCalls,
    hasActiveCall,
    isJoining: globalIsJoiningReadonly,
    formattedCallDuration,
  };
};

// Root-mount composable. Call once at the dashboard root (FloatingCallWidget
// is the natural anchor — always mounted, lifetime spans the whole session).
// This is the only path that registers global window/Twilio listeners and
// owns the duration Timer.
export function useCallSession() {
  const store = useStore();
  const callsStore = useCallsStore();
  const whatsappSession = useWhatsappCallSession();
  const { t } = useI18n();

  const reactive = buildReactiveSurface(callsStore);

  // Cable broadcasts (voice_call.incoming / message.created) are one-shot, so
  // on a hard refresh they leave the calls store empty. Seed it from any
  // ringing voice_call message in the conversation cache. handleVoiceCallCreated
  // skips calls already dismissed (locally or via a real-time accepted/ended
  // event) so they don't re-pop on the next conversation update.
  const seedCallsFromHydratedMessages = () => {
    // FORK: skip unchanged threads and inboxes without voice
    seedVoiceCallsFromHydratedMessagesHelper({
      conversations: store.getters.getAllConversations || [],
      inboxes: store.getters['inboxes/getInboxes'] || [],
      currentUserId: store.getters.getCurrentUserID,
      currentUserAvailability: store.getters.getCurrentUserAvailability,
    });
  };
  seedCallsFromHydratedMessagesFn = seedCallsFromHydratedMessages;

  watch(
    reactive.hasActiveCall,
    active => {
      if (active) {
        globalDurationTimer?.start();
      } else {
        globalDurationTimer?.stop();
        globalCallDuration.value = 0;
      }
    },
    { immediate: true }
  );

  onMounted(() => {
    attachGlobalsOnFirstMount(callsStore);
    seedCallsFromHydratedMessages();
  });

  // Re-seed when conversations stream in after mount; addCall merges by callSid
  // and dismissed sids are filtered, so this is idempotent. Debounced so rapid
  // message/conversation updates don't re-scan the full cache on every tick.
  watch(
    () => store.getters.getAllConversations?.length,
    () => scheduleSeedCallsFromHydratedMessages()
  );

  watch(
    () => store.getters.getSelectedChat?.messages?.length,
    () => scheduleSeedCallsFromHydratedMessages()
  );

  onUnmounted(() => {
    seedCallsFromHydratedMessagesFn = null;
    detachGlobalsOnLastUnmount();
  });

  const actions = buildCallActions({ callsStore, whatsappSession, t });

  return { ...reactive, ...actions };
}

// Lightweight consumer for components that need to read state and trigger
// actions but should NOT mount global listeners (e.g., per-message bubbles
// rendered in a thread). Reads from the same module-level state that
// useCallSession owns, so the duration timer and dismissed set stay coherent.
export function useCallActions() {
  const callsStore = useCallsStore();
  const whatsappSession = useWhatsappCallSession();
  const { t } = useI18n();

  const reactive = buildReactiveSurface(callsStore);
  const actions = buildCallActions({ callsStore, whatsappSession, t });

  return { ...reactive, ...actions };
}
