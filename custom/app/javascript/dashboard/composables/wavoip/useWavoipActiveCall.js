import { readonly, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { wireCallDiagnostics } from 'customDashboard/lib/wavoip/wavoipCallDiagnostics';
import { removeWavoipCallFromStore } from 'customDashboard/lib/wavoip/wavoipCallTeardown';

let activeSdkCall = null;
let activeProviderCallId = null;
let activeInboxId = null;
let ringingSdkCall = null;
let ringingProviderCallId = null;
let ringingInboxId = null;
let outboundInitiationInboxId = null;
let outboundInitiationConversationId = null;
let activeCallTranslateFn = null;
let activeDiagnosticsUnwire = null;
let ringingDiagnosticsUnwire = null;
let activeConnectionStatusHandler = null;
let activeEndedHandler = null;
let activeStatusHandler = null;
const TERMINAL_SDK_STATUSES = ['ENDED', 'FAILED', 'REJECTED', 'NOT_ANSWERED'];

const isMuted = ref(false);
const mediaConnectionStatus = ref(null);
const callLegStatus = ref(null);

const clearActiveCallHandlers = () => {
  if (activeSdkCall) {
    if (activeConnectionStatusHandler) {
      activeSdkCall.off?.('connectionStatus', activeConnectionStatusHandler);
    }
    if (activeEndedHandler) {
      activeSdkCall.off?.('ended', activeEndedHandler);
    }
    if (activeStatusHandler) {
      activeSdkCall.off?.('status', activeStatusHandler);
    }
  }
  activeConnectionStatusHandler = null;
  activeEndedHandler = null;
  activeStatusHandler = null;
  activeDiagnosticsUnwire?.();
  activeDiagnosticsUnwire = null;
};

const clearRingingCallHandlers = () => {
  ringingDiagnosticsUnwire?.();
  ringingDiagnosticsUnwire = null;
};

export const clearActiveCall = () => {
  clearActiveCallHandlers();
  activeSdkCall = null;
  activeProviderCallId = null;
  activeInboxId = null;
  isMuted.value = false;
  mediaConnectionStatus.value = null;
  callLegStatus.value = null;
};

export const clearRingingOutgoingCall = () => {
  clearRingingCallHandlers();
  ringingSdkCall = null;
  ringingProviderCallId = null;
  ringingInboxId = null;
};

export const beginOutboundInitiation = (inboxId, conversationId) => {
  outboundInitiationInboxId = inboxId ?? null;
  outboundInitiationConversationId = conversationId ?? null;
};

export const endOutboundInitiation = () => {
  outboundInitiationInboxId = null;
  outboundInitiationConversationId = null;
};

export const isOutboundInitiationActive = inboxId =>
  outboundInitiationInboxId != null &&
  (inboxId == null || outboundInitiationInboxId === inboxId);

export const getOutboundInitiationConversationId = () =>
  outboundInitiationConversationId;

export const setRingingOutgoingCall = (
  sdkCall,
  { providerCallId, inboxId } = {}
) => {
  if (ringingSdkCall && ringingSdkCall !== sdkCall) {
    clearRingingCallHandlers();
  }

  ringingSdkCall = sdkCall;
  ringingProviderCallId = providerCallId || null;
  if (inboxId) ringingInboxId = inboxId;
  ringingDiagnosticsUnwire = wireCallDiagnostics(sdkCall, {
    inboxId: ringingInboxId,
    callId: providerCallId,
    translateFn: activeCallTranslateFn,
  });
};

export const setActiveCall = (sdkCall, { providerCallId, inboxId } = {}) => {
  clearActiveCallHandlers();

  activeSdkCall = sdkCall;
  activeProviderCallId = providerCallId || null;
  if (inboxId) activeInboxId = inboxId;
  isMuted.value = false;
  mediaConnectionStatus.value = sdkCall?.connectionStatus || null;
  callLegStatus.value = sdkCall?.status || null;

  activeDiagnosticsUnwire = wireCallDiagnostics(sdkCall, {
    inboxId: activeInboxId,
    callId: providerCallId,
    translateFn: activeCallTranslateFn,
  });

  const teardownActiveFromSdk = () => {
    if (activeSdkCall !== sdkCall) return;
    const endedCallId = activeProviderCallId;
    clearActiveCall();
    removeWavoipCallFromStore(endedCallId);
  };

  // Local transport: reconnecting is recoverable; disconnected means the SDK
  // gave up (≈30s) and the call is lost.
  activeConnectionStatusHandler = status => {
    mediaConnectionStatus.value = status;
    if (status === 'disconnected') teardownActiveFromSdk();
  };
  activeEndedHandler = teardownActiveFromSdk;
  // WhatsApp media-leg drop (`DISCONNECTED`) is recoverable — later `ACTIVE`
  // restores audio. Only terminal CallStatus values hang up the widget.
  activeStatusHandler = status => {
    callLegStatus.value = status || null;
    if (TERMINAL_SDK_STATUSES.includes(status)) teardownActiveFromSdk();
  };

  sdkCall?.on?.('connectionStatus', activeConnectionStatusHandler);
  sdkCall?.on?.('ended', activeEndedHandler);
  sdkCall?.on?.('status', activeStatusHandler);
};

export const getActiveProviderCallId = () => activeProviderCallId;

export const getRingingProviderCallId = () => ringingProviderCallId;

export const getActiveInboxId = () => activeInboxId || ringingInboxId;

export const isWavoipSdkCallOwned = callSid =>
  !!callSid &&
  (activeProviderCallId === callSid || ringingProviderCallId === callSid);

export const endActiveCall = async callIdOverride => {
  const targetId =
    callIdOverride || activeProviderCallId || ringingProviderCallId;
  const callToEnd =
    (activeSdkCall &&
      (!callIdOverride || activeProviderCallId === callIdOverride) &&
      activeSdkCall) ||
    (ringingSdkCall &&
      (!callIdOverride || ringingProviderCallId === callIdOverride) &&
      ringingSdkCall);
  if (callToEnd) {
    try {
      await callToEnd.end?.();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.debug('[Wavoip] end SDK call failed', error);
    }
    clearActiveCall();
    clearRingingOutgoingCall();
    return targetId;
  }
  return targetId;
};

export function useWavoipActiveCall() {
  const { t } = useI18n();
  activeCallTranslateFn = t;

  const setMuted = muted => {
    isMuted.value = muted;
    if (!activeSdkCall) return false;
    const action = muted ? activeSdkCall.mute?.() : activeSdkCall.unmute?.();
    Promise.resolve(action).catch(error => {
      // eslint-disable-next-line no-console
      console.debug('[Wavoip] mute toggle failed', error);
    });
    return true;
  };

  const hasActiveCall = () => !!activeSdkCall;

  return {
    isMuted: readonly(isMuted),
    mediaConnectionStatus: readonly(mediaConnectionStatus),
    callLegStatus: readonly(callLegStatus),
    setActiveCall,
    clearActiveCall,
    setMuted,
    endActiveCall,
    hasActiveCall,
    getActiveProviderCallId,
  };
}
