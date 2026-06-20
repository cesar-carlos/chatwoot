import { readonly, ref } from 'vue';

let activeSdkCall = null;
let activeProviderCallId = null;
const isMuted = ref(false);

export const clearActiveCall = () => {
  activeSdkCall = null;
  activeProviderCallId = null;
  isMuted.value = false;
};

export const setActiveCall = (sdkCall, { providerCallId } = {}) => {
  activeSdkCall = sdkCall;
  activeProviderCallId = providerCallId || null;
  isMuted.value = false;

  sdkCall?.on?.('ended', () => {
    if (activeSdkCall === sdkCall) clearActiveCall();
  });
};

export const getActiveProviderCallId = () => activeProviderCallId;

export const endActiveCall = async callIdOverride => {
  const targetId = callIdOverride || activeProviderCallId;
  if (activeSdkCall) {
    try {
      await activeSdkCall.end?.();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.debug('[Wavoip] end active SDK call failed', error);
    }
    clearActiveCall();
    return targetId;
  }
  return targetId;
};

export function useWavoipActiveCall() {
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
    setActiveCall,
    clearActiveCall,
    setMuted,
    endActiveCall,
    hasActiveCall,
    getActiveProviderCallId,
  };
}
