import { readonly, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { wireCallDiagnostics } from 'customDashboard/lib/wavoip/wavoipCallDiagnostics';

let activeSdkCall = null;
let activeProviderCallId = null;
let activeInboxId = null;
let ringingSdkCall = null;
let ringingProviderCallId = null;
let activeCallTranslateFn = null;
const isMuted = ref(false);
const mediaConnectionStatus = ref(null);

export const clearActiveCall = () => {
  activeSdkCall = null;
  activeProviderCallId = null;
  activeInboxId = null;
  isMuted.value = false;
  mediaConnectionStatus.value = null;
};

export const clearRingingOutgoingCall = () => {
  ringingSdkCall = null;
  ringingProviderCallId = null;
  activeInboxId = null;
};

export const setRingingOutgoingCall = (
  sdkCall,
  { providerCallId, inboxId } = {}
) => {
  ringingSdkCall = sdkCall;
  ringingProviderCallId = providerCallId || null;
  if (inboxId) activeInboxId = inboxId;
  wireCallDiagnostics(sdkCall, {
    inboxId: activeInboxId,
    callId: providerCallId,
    translateFn: activeCallTranslateFn,
  });
};

export const setActiveCall = (sdkCall, { providerCallId, inboxId } = {}) => {
  activeSdkCall = sdkCall;
  activeProviderCallId = providerCallId || null;
  if (inboxId) activeInboxId = inboxId;
  isMuted.value = false;
  mediaConnectionStatus.value = sdkCall?.connectionStatus || null;

  wireCallDiagnostics(sdkCall, {
    inboxId: activeInboxId,
    callId: providerCallId,
    translateFn: activeCallTranslateFn,
  });

  sdkCall?.on?.('connectionStatus', status => {
    mediaConnectionStatus.value = status;
  });
  sdkCall?.on?.('ended', () => {
    if (activeSdkCall === sdkCall) clearActiveCall();
  });
};

export const getActiveProviderCallId = () => activeProviderCallId;

export const endActiveCall = async callIdOverride => {
  const targetId =
    callIdOverride || activeProviderCallId || ringingProviderCallId;
  const callToEnd = activeSdkCall || ringingSdkCall;
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
    if (muted) activeSdkCall.mute?.();
    else activeSdkCall.unmute?.();
    return true;
  };

  const hasActiveCall = () => !!activeSdkCall;

  return {
    isMuted: readonly(isMuted),
    mediaConnectionStatus: readonly(mediaConnectionStatus),
    setActiveCall,
    clearActiveCall,
    setMuted,
    endActiveCall,
    hasActiveCall,
    getActiveProviderCallId,
  };
}
