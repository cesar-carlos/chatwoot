import {
  CONTENT_TYPES,
  VOICE_CALL_STATUS,
} from 'dashboard/components-next/message/constants';
import { MESSAGE_TYPE } from 'shared/constants/messages';
import { useCallsStore } from 'dashboard/stores/calls';
import types from 'dashboard/store/mutation-types';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  handleWebRtcRemoteEnd,
  isLocalWebRtcCall,
} from 'dashboard/composables/useWebRtcCallSession';
// FORK: Wavoip inbound ring routing and call-direction normalization
import { shouldReceiveWavoipInboundRing } from 'customDashboard/lib/wavoip/wavoipInboxCallRouting';
import {
  isOutboundInitiationActive,
  isWavoipSdkCallOwned,
} from 'customDashboard/composables/wavoip/useWavoipActiveCall';
import { normalizeCallDirection } from 'customDashboard/lib/voice/voiceCallDirection';
import { getRuntimeStore as getDashboardStore } from 'dashboard/store/runtimeStore';
import {
  isCallDismissed,
  markCallDismissed,
} from 'dashboard/helper/voiceCallDismissed';

export { isCallDismissed, markCallDismissed };

export const TERMINAL_STATUSES = [
  'completed',
  'busy',
  'failed',
  'rejected',
  'no-answer',
  'canceled',
  'missed',
  'ended',
];

// A message.created for a ringing call is queued through ActionCableBroadcastJob and can
// be delivered after the call has already been accepted/ended via a synchronous broadcast.
// Track dismissed call sids at module scope so that late, stale "ringing" snapshot doesn't
// resurrect a card every caller of handleVoiceCallCreated (hydration and real-time alike)
// has already cleared.
// Which Twilio call (if any) this tab is actively joining/owns. Must be set
// synchronously BEFORE the join API call — mirrors useWhatsappCallSession's
// activeCallId — so the account-wide voice_call.accepted broadcast (which can
// arrive before the join promise resolves) doesn't mistake this tab's own
// call for a sibling tab's and tear it down mid-join.
let localCallSid = null;
export const markLocalCall = callSid => {
  localCallSid = callSid || null;
};
export const isLocalCall = callSid =>
  !!callSid && localCallSid != null && callSid === localCallSid;
export const clearLocalCall = callSid => {
  if (localCallSid === callSid) localCallSid = null;
};

export const isInbound = direction => direction === 'inbound';

const isVoiceCallMessage = message => {
  return CONTENT_TYPES.VOICE_CALL === message?.content_type;
};

// FORK: ignore stale Wavoip ringing messages (ghost widgets)
// Wavoip calls rely entirely on the provider's webhook to reach a terminal
// status. When that webhook never arrives (SDK-only hangups, dropped
// webhooks), the Call row is stuck "ringing" forever and keeps resurfacing
// as a ghost incoming/outgoing widget every time the conversation hydrates
// (e.g. after the outbound-call flow refreshes the conversation). Ignore
// ringing voice_call messages once they're older than a generous window —
// well above any configured ring timeout — so stale rows stop haunting the UI
// while the backend safety-net job catches up and marks them no_answer.
const WAVOIP_STALE_RINGING_MS = 3 * 60 * 1000;
const WHATSAPP_STALE_RINGING_MS = 3 * 60 * 1000;

export const isStaleWavoipRingingMessage = message => {
  const call = message?.call;
  if (call?.provider !== VOICE_CALL_PROVIDERS.WAVOIP) return false;
  if (call?.status !== 'ringing') return false;

  const createdAtMs = (message?.created_at || 0) * 1000;
  if (!createdAtMs) return false;

  return Date.now() - createdAtMs > WAVOIP_STALE_RINGING_MS;
};

export const isStaleWhatsappRingingMessage = message => {
  const call = message?.call;
  if (call?.provider !== VOICE_CALL_PROVIDERS.WHATSAPP) return false;
  if (call?.status !== 'ringing') return false;

  const createdAtMs = (message?.created_at || 0) * 1000;
  if (!createdAtMs) return false;

  return Date.now() - createdAtMs > WHATSAPP_STALE_RINGING_MS;
};

export const isStaleRingingVoiceMessage = message =>
  isStaleWavoipRingingMessage(message) ||
  isStaleWhatsappRingingMessage(message);

const shouldSkipCall = (callDirection, senderId, currentUserId) => {
  return callDirection === 'outbound' && senderId !== currentUserId;
};

const extractAssigneeId = conversation => {
  return conversation?.assignee_id || conversation?.meta?.assignee?.id || null;
};

const isAssignedToAnotherAgent = (assigneeId, currentUserId) => {
  if (currentUserId == null) return false;
  return !!assigneeId && assigneeId !== currentUserId;
};

const shouldShowCall = ({
  callDirection,
  senderId,
  assigneeId,
  currentUserId,
}) => {
  if (shouldSkipCall(callDirection, senderId, currentUserId)) return false;
  // Outbound calls are scoped to the initiator via shouldSkipCall; the
  // conversation may be auto-assigned to a different agent on creation, so
  // skip the assignee filter for outbound to avoid hiding the caller's own widget.
  if (callDirection === 'outbound') return true;
  return !isAssignedToAnotherAgent(assigneeId, currentUserId);
};

// Offline/busy agents shouldn't get a ringing popup for inbound calls, but
// outbound calls always belong to the initiator regardless of their status,
// and existing (already-surfaced) calls keep going so a status change
// mid-call doesn't yank away an active widget.
const shouldRingInbound = (callDirection, currentUserAvailability) => {
  if (callDirection === 'outbound') return true;
  return currentUserAvailability === 'online';
};

function extractCallerSnapshot(message) {
  // Snapshot caller info from the message at add-time so the widget can keep
  // rendering it after the user navigates away from a conversation list that
  // had the conversation hydrated (and Vuex evicts it from the store).
  // Only incoming messages carry the contact as the sender; on outbound calls
  // the sender is the initiating agent, so skip the snapshot and let the widget
  // fall back to the conversation's contact (conversation.meta.sender).
  if (message?.message_type !== MESSAGE_TYPE.INCOMING) return null;
  const sender = message?.sender;
  if (!sender) return null;
  return {
    name: sender.name,
    phone: sender.phone_number,
    avatar: sender.avatar || sender.thumbnail,
    additionalAttributes: sender.additional_attributes || {},
  };
}

function extractCallData(message) {
  const call = message?.call || {};
  return {
    callSid: call.provider_call_id,
    callId: call.id,
    provider: call.provider,
    status: call.status,
    callDirection: normalizeCallDirection(call.direction),
    conversationId: message?.conversation_id,
    inboxId: message?.inbox_id ?? message?.conversation?.inbox_id,
    assigneeId: extractAssigneeId(message?.conversation),
    senderId: message?.sender?.id,
    caller: extractCallerSnapshot(message),
  };
}

export function handleVoiceCallCreated(
  message,
  currentUserId,
  currentUserAvailability
) {
  if (!isVoiceCallMessage(message)) return;
  if (isStaleRingingVoiceMessage(message)) return;

  const {
    callSid,
    callId,
    provider,
    status,
    callDirection,
    conversationId,
    inboxId,
    assigneeId,
    senderId,
  } = extractCallData(message);

  if (isCallDismissed(callSid)) return;

  // A voice_call message can be created already terminal when the caller hangs
  // up before connect. Only ring while the call is actually ringing; mirrors the
  // guard in seedCallsFromHydratedMessages.
  if (status !== VOICE_CALL_STATUS.RINGING) return;

  if (
    !shouldShowCall({
      callDirection,
      senderId,
      assigneeId,
      currentUserId,
    })
  ) {
    return;
  }

  if (!shouldRingInbound(callDirection, currentUserAvailability)) return;

  // FORK: suppress Wavoip inbound ring during outbound initiation / inbox routing
  if (
    provider === VOICE_CALL_PROVIDERS.WAVOIP &&
    callDirection === 'inbound' &&
    isOutboundInitiationActive(inboxId)
  ) {
    return;
  }

  if (
    provider === VOICE_CALL_PROVIDERS.WAVOIP &&
    callDirection === 'inbound' &&
    !shouldReceiveWavoipInboundRing({
      // FORK: lazy store access avoids conversations → voice → store cycle
      inbox: getDashboardStore()?.getters['inboxes/getInbox']?.(inboxId),
      isAdministrator:
        getDashboardStore()?.getters.getCurrentRole === 'administrator',
      availability: currentUserAvailability,
    })
  ) {
    return;
  }

  const callsStore = useCallsStore();
  callsStore.addCall({
    callSid,
    callId,
    provider,
    conversationId,
    inboxId,
    callDirection,
    senderId,
    caller: extractCallerSnapshot(message),
  });
}

export function handleVoiceCallUpdated(
  commit,
  message,
  currentUserId,
  currentUserAvailability
) {
  if (!isVoiceCallMessage(message)) return;

  const {
    callSid,
    callId,
    provider,
    status,
    callDirection,
    conversationId,
    inboxId,
    assigneeId,
    senderId,
  } = extractCallData(message);

  const callsStore = useCallsStore();

  // Guard against a still-queued ringing message.created arriving after this
  // terminal update, same as the accepted/ended broadcast handlers.
  if (TERMINAL_STATUSES.includes(status)) markCallDismissed(callSid);

  callsStore.handleCallStatusChanged({ callSid, status, conversationId });

  if (
    provider === VOICE_CALL_PROVIDERS.WHATSAPP &&
    TERMINAL_STATUSES.includes(status) &&
    isLocalWebRtcCall(callId)
  ) {
    handleWebRtcRemoteEnd(callId);
  }

  commit(types.UPDATE_MESSAGE_CALL_STATUS, {
    conversationId,
    callStatus: status,
    callSid,
  });

  if (
    !shouldShowCall({
      callDirection,
      senderId,
      assigneeId,
      currentUserId,
    })
  ) {
    // FORK: don't remove widget while Wavoip SDK session is still live
    // Outbound Wavoip messages are created with a null sender (accepted_by_agent
    // is not set at call-creation time), so shouldShowCall always returns false
    // for every agent. The SDK is the source of truth for whether the session is
    // still live; don't yank the widget while the SDK is still ringing.
    if (!isWavoipSdkCallOwned(callSid)) {
      callsStore.removeCall(callSid);
    }
    return;
  }

  if (status === 'ringing') {
    if (isStaleRingingVoiceMessage(message)) return;
    if (!shouldRingInbound(callDirection, currentUserAvailability)) return;

    callsStore.addCall({
      callSid,
      callId,
      provider,
      conversationId,
      inboxId,
      callDirection,
      senderId,
      caller: extractCallerSnapshot(message),
    });
  }
}

export function syncConversationCallVisibility(conversation, currentUserId) {
  const assigneeId = extractAssigneeId(conversation);
  if (!isAssignedToAnotherAgent(assigneeId, currentUserId)) return;

  // Outbound calls belong to the initiator regardless of who the conversation
  // is currently assigned to (auto-assignment may flip mid-call). Mirror
  // shouldShowCall's outbound exception so an in-progress outbound call isn't
  // ripped out from under the caller when the conversation reassigns.
  const callsStore = useCallsStore();
  const callsToRemove = callsStore.calls.filter(
    call =>
      call.conversationId === conversation.id &&
      !shouldShowCall({
        callDirection: call.callDirection,
        senderId: call.senderId,
        assigneeId,
        currentUserId,
      })
  );
  callsToRemove.forEach(call => callsStore.removeCall(call.callSid));
}
