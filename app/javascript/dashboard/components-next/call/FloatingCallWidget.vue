<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import {
  useCallSession,
  isCallRingtoneSilenced,
} from 'dashboard/composables/useCallSession';
import { useCallRingtonePreference } from 'dashboard/composables/useCallRingtonePreference';
import { setWhatsappCallMuted } from 'dashboard/composables/useWhatsappCallSession';
// FORK: Wavoip active call composables (mute, device status)
import { useWavoipActiveCall } from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
// FORK: Wavoip outbound ringback while destination has not answered
import {
  INBOUND_RINGTONE_VOLUME,
  startWavoipOutboundRingback,
  stopWavoipOutboundRingback,
  shouldPlayWavoipOutboundRingback,
} from 'customDashboard/lib/wavoip/wavoipOutboundRingback';
import TwilioVoiceClient from 'dashboard/api/channel/voice/twilioVoiceClient';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import WindowVisibilityHelper from 'dashboard/helper/AudioAlerts/WindowVisibilityHelper';
import CallCard from 'dashboard/components-next/call/CallCard.vue';
import countriesList from 'shared/constants/countries.js';

const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const {
  activeCall,
  incomingCalls,
  hasActiveCall,
  isJoining,
  joinCall,
  endCall: endCallSession,
  rejectIncomingCall,
  dismissCall,
  formattedCallDuration,
} = useCallSession();

const { isRingtoneMuted, initPreference, toggleRingtoneMute } =
  useCallRingtonePreference();

onMounted(() => {
  initPreference();
});

// Mute routes by provider: WhatsApp toggles the local mic track, Twilio uses
// the Voice SDK connection's native mute. Both surface the same button.
const isWhatsappActive = computed(
  () => activeCall.value?.provider === VOICE_CALL_PROVIDERS.WHATSAPP
);
// FORK: Wavoip mute and connection status
const isWavoipActive = computed(
  () => activeCall.value?.provider === VOICE_CALL_PROVIDERS.WAVOIP
);
const {
  setMuted: setWavoipMuted,
  isMuted: wavoipIsMuted,
  mediaConnectionStatus,
  callLegStatus,
} = useWavoipActiveCall();
// Wavoip owns its own isMuted state (reset on setActiveCall/clearActiveCall,
// and it's the value actually wired to the SDK's mute/unmute calls) — read it
// directly instead of mirroring it into a second local ref that could drift
// out of sync with the composable.
const localIsMuted = ref(false);
const isMuted = computed(() =>
  isWavoipActive.value ? wavoipIsMuted.value : localIsMuted.value
);
const primaryIncomingCall = computed(() =>
  hasActiveCall.value ? null : incomingCalls.value[0] || null
);

const bannerInboxId = computed(
  () => activeCall.value?.inboxId || primaryIncomingCall.value?.inboxId
);

const deviceConnectionStatus = computed(() => {
  if (!bannerInboxId.value) return null;
  return getWavoipDeviceStatus(bannerInboxId.value).connectionStatus.value;
});

const connectionBannerMessage = computed(() => {
  if (isWavoipActive.value && callLegStatus.value === 'DISCONNECTED') {
    return t('CONVERSATION.WAVOIP_CALL.RECONNECTING');
  }
  if (isWavoipActive.value && mediaConnectionStatus.value === 'reconnecting') {
    return t('CONVERSATION.WAVOIP_CALL.RECONNECTING');
  }
  if (deviceConnectionStatus.value === 'reconnecting') {
    return t('CONVERSATION.WAVOIP_CALL.DEVICE_RECONNECTING');
  }
  if (deviceConnectionStatus.value === 'disconnected') {
    return t('CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED');
  }
  return null;
});

const stackedIncomingCalls = computed(() =>
  hasActiveCall.value ? incomingCalls.value : incomingCalls.value.slice(1)
);

// Cap the number of full stacked cards rendered so a burst of simultaneous
// ringing calls doesn't push the widget off-screen — summarize the rest in
// a compact "+N" pill instead.
const MAX_VISIBLE_STACKED_CARDS = 2;
const visibleStackedCalls = computed(() =>
  stackedIncomingCalls.value.slice(0, MAX_VISIBLE_STACKED_CARDS)
);
const overflowStackedCallsCount = computed(() =>
  Math.max(0, stackedIncomingCalls.value.length - MAX_VISIBLE_STACKED_CARDS)
);

const mainCardState = computed(() => {
  if (hasActiveCall.value) return VOICE_CALL_DIRECTION.ONGOING;
  const direction = primaryIncomingCall.value?.callDirection;
  return direction === VOICE_CALL_DIRECTION.OUTBOUND
    ? VOICE_CALL_DIRECTION.OUTGOING
    : VOICE_CALL_DIRECTION.INCOMING;
});

// Stacked cards are always non-active (ringing) calls, so reflect each call's
// real direction. An outbound call must render as OUTGOING — otherwise it shows
// the incoming-only dismiss (✕) control and the agent could drop it locally
// without terminating, leaving the customer ringing with no widget to end it.
const stackedCardState = call =>
  call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND
    ? VOICE_CALL_DIRECTION.OUTGOING
    : VOICE_CALL_DIRECTION.INCOMING;

const toggleMute = () => {
  const nextMuted = !isMuted.value;
  if (isWhatsappActive.value) {
    localIsMuted.value = nextMuted;
    setWhatsappCallMuted(nextMuted);
  } else if (isWavoipActive.value) {
    // setWavoipMuted updates the composable's own isMuted ref, which is what
    // `isMuted` reads from for Wavoip calls above.
    setWavoipMuted(nextMuted);
  } else {
    localIsMuted.value = nextMuted;
    TwilioVoiceClient.setMuted(nextMuted);
  }
};

watch(hasActiveCall, active => {
  if (!active) localIsMuted.value = false;
});

// Convert ISO 3166-1 alpha-2 country code (e.g. "US") to its regional indicator
// flag emoji. Returns empty string if the code is missing or malformed.
const countryCodeToFlag = code => {
  if (!code || code.length !== 2) return '';
  const base = 0x1f1e6;
  const offset = 'A'.charCodeAt(0);
  return String.fromCodePoint(
    ...code
      .toUpperCase()
      .split('')
      .map(c => base + (c.charCodeAt(0) - offset))
  );
};

const getCallInfo = call => {
  const conversation = store.getters.getConversationById(call?.conversationId);
  // Look up inbox from the call's own inboxId — the conversation can drop out
  // of the Vuex store when the user navigates between inbox views, so going
  // through `conversation.inbox_id` would lose the inbox name (and fall back
  // to the literal "Customer support" string).
  const inbox = store.getters['inboxes/getInbox'](call?.inboxId);
  const sender = conversation?.meta?.sender;
  // `caller` is the snapshot captured when the call first landed (from the
  // message sender or the WhatsApp cable payload). It outlives the
  // conversation being in the store, so prefer it for display.
  const caller = call?.caller;
  const additional =
    sender?.additional_attributes || caller?.additionalAttributes || {};
  const city = additional.city || '';
  const countryCode = additional.country_code || '';
  const country =
    additional.country ||
    countriesList.find(c => c.id === countryCode.toUpperCase())?.name ||
    '';
  // Prefer the richest available location string ("City, Country"); fall back to
  // whichever single field is present; finally fall back to the inbox name so
  // there's always something to show.
  const locationParts = [city, country].filter(Boolean);
  const location =
    locationParts.join(', ') ||
    inbox?.name ||
    t('CONVERSATION.VOICE_WIDGET.CUSTOMER_SUPPORT');
  return {
    conversation,
    inbox,
    contactName:
      caller?.name ||
      sender?.name ||
      caller?.phone ||
      sender?.phone_number ||
      t('CONVERSATION.VOICE_WIDGET.UNKNOWN_CALLER'),
    phoneNumber: caller?.phone || sender?.phone_number || '',
    inboxName: inbox?.name || t('CONVERSATION.VOICE_WIDGET.CUSTOMER_SUPPORT'),
    location,
    countryFlag: countryCodeToFlag(countryCode),
    hasLocation: locationParts.length > 0,
    avatar: caller?.avatar || sender?.avatar || sender?.thumbnail,
  };
};

const goToConversation = call => {
  const conversationId = call?.conversationId;
  const accountId = route.params.accountId;
  if (!conversationId || !accountId) return;
  router.push({
    path: frontendURL(conversationUrl({ accountId, id: conversationId })),
  });
};

const handleEndCall = async () => {
  const call = activeCall.value;
  if (!call) return;

  const inboxId = call.inboxId || getCallInfo(call).conversation?.inbox_id;
  if (!inboxId) return;

  await endCallSession({
    conversationId: call.conversationId,
    inboxId,
    callSid: call.callSid,
  });
};

const handleJoinCall = async call => {
  if (!call || isJoining.value) return;
  const { conversation } = getCallInfo(call);

  if (hasActiveCall.value) {
    await handleEndCall();
  }

  // The conversation may not be hydrated yet (post-refresh seeding path);
  // call.inboxId already carries what joinCall needs.
  const result = await joinCall({
    conversationId: call.conversationId,
    inboxId: call.inboxId || conversation?.inbox_id,
    callSid: call.callSid,
  });

  if (result) {
    goToConversation(call);
  }
};

// Auto-join outbound calls when window is visible. WhatsApp outbound has no
// separate join step (the offer was sent at initiate time and the answer is
// applied directly by the cable handler), so this only covers Twilio.
watch(
  () => incomingCalls.value[0],
  call => {
    if (
      call?.callDirection === VOICE_CALL_DIRECTION.OUTBOUND &&
      call?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP &&
      // FORK: skip auto-join for Wavoip outbound (SDK owns the session)
      call?.provider !== VOICE_CALL_PROVIDERS.WAVOIP &&
      !hasActiveCall.value &&
      WindowVisibilityHelper.isWindowVisible()
    ) {
      handleJoinCall(call);
    }
  },
  { immediate: true }
);

// Loop the inbound ringtone while unanswered. FORK: Wavoip outbound ringback
// is owned by wavoipOutboundRingback.js (started from the click path so
// autoplay is not blocked by async FloatingCallWidget mount).
const ringtone = new Audio(RINGTONE_URL);
ringtone.loop = true;
ringtone.volume = INBOUND_RINGTONE_VOLUME;

const stopRingtone = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
  ringtone.volume = INBOUND_RINGTONE_VOLUME;
};

// Returns true only for calls this agent hasn't silenced locally. When the
// agent presses reject/dismiss the SID is added to ringtoneSilencedCallSids
// immediately (before the async provider round-trip), so the audio stops right
// away. Other agents and devices are unaffected.
const shouldRingForCall = call =>
  call.callDirection !== VOICE_CALL_DIRECTION.OUTBOUND &&
  !isCallRingtoneSilenced(call.callSid) &&
  // FORK: silence ringtone by Wavoip offer id alias
  !isCallRingtoneSilenced(call.wavoipOfferId);

const ringingInbound = computed(
  () => !isRingtoneMuted.value && incomingCalls.value.some(shouldRingForCall)
);

// FORK: soft ringback while Wavoip outbound is unanswered (not Meta/Twilio).
// Do NOT gate on isRingtoneMuted — that bell only silences inbound ringtone.
const ringingWavoipOutbound = computed(() =>
  incomingCalls.value.some(call =>
    shouldPlayWavoipOutboundRingback(call, {
      isSilenced: isCallRingtoneSilenced,
    })
  )
);

watch(
  () => ({
    inbound: ringingInbound.value && !hasActiveCall.value,
    outbound: ringingWavoipOutbound.value && !hasActiveCall.value,
  }),
  (curr, prev) => {
    if (curr.inbound) {
      stopWavoipOutboundRingback();
      ringtone.volume = INBOUND_RINGTONE_VOLUME;
      ringtone.play().catch(() => {});
      return;
    }
    stopRingtone();
    if (curr.outbound) {
      // Backup if click-path start was skipped; usually already playing.
      startWavoipOutboundRingback();
      return;
    }
    // Only stop when outbound was ringing and stopped (answer / dismiss).
    // Do not stop on "never outbound" — that would kill click-path ringback
    // during connect/startCall before addCall mounts this widget.
    if (prev?.outbound) {
      stopWavoipOutboundRingback();
    }
  },
  { immediate: true, deep: true }
);

onBeforeUnmount(() => {
  stopRingtone();
  stopWavoipOutboundRingback();
});
</script>

<template>
  <Transition name="call-widget">
    <div
      v-if="incomingCalls.length || hasActiveCall"
      class="fixed ltr:right-4 rtl:left-4 bottom-4 z-50 flex flex-col gap-3 w-[400px]"
    >
      <div
        v-if="connectionBannerMessage"
        class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 px-3 py-2 text-xs text-n-ruby-11"
      >
        {{ connectionBannerMessage }}
      </div>

      <!-- Stacked incoming calls (shown above the primary card) -->
      <CallCard
        v-for="call in visibleStackedCalls"
        :key="call.callSid"
        :call="call"
        :state="stackedCardState(call)"
        :call-info="getCallInfo(call)"
        :is-joining="isJoining"
        :is-ringtone-muted="isRingtoneMuted"
        @accept="handleJoinCall(call)"
        @reject="rejectIncomingCall(call.callSid)"
        @dismiss="dismissCall(call.callSid)"
        @toggle-ringtone-mute="toggleRingtoneMute"
        @go-to-conversation="goToConversation(call)"
      />
      <div
        v-if="overflowStackedCallsCount > 0"
        class="rounded-lg bg-n-solid-2 px-3 py-2 text-center text-xs text-n-slate-11"
      >
        {{
          t('CONVERSATION.WAVOIP_CALL.INCOMING_CALLS_OVERFLOW', {
            count: overflowStackedCallsCount,
          })
        }}
      </div>

      <!-- Main Call Widget -->
      <CallCard
        v-if="hasActiveCall || primaryIncomingCall"
        :call="activeCall || primaryIncomingCall"
        :state="mainCardState"
        :call-info="getCallInfo(activeCall || primaryIncomingCall)"
        :duration="hasActiveCall ? formattedCallDuration : ''"
        :is-muted="isMuted"
        :show-mute="hasActiveCall"
        :is-joining="isJoining"
        :is-ringtone-muted="isRingtoneMuted"
        @accept="handleJoinCall(primaryIncomingCall)"
        @reject="rejectIncomingCall(primaryIncomingCall?.callSid)"
        @dismiss="dismissCall(primaryIncomingCall?.callSid)"
        @toggle-ringtone-mute="toggleRingtoneMute"
        @end="handleEndCall"
        @toggle-mute="toggleMute"
        @go-to-conversation="
          goToConversation(activeCall || primaryIncomingCall)
        "
      />
    </div>
  </Transition>
</template>
