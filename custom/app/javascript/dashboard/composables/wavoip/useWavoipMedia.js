import { readonly, ref } from 'vue';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';

const mediaByInbox = new Map();

const ensureMediaState = inboxId => {
  if (!mediaByInbox.has(inboxId)) {
    mediaByInbox.set(inboxId, {
      inputDevices: ref([]),
      outputDevices: ref([]),
      activeInputId: ref(null),
      activeOutputId: ref(null),
    });
  }
  return mediaByInbox.get(inboxId);
};

export function getWavoipMediaForInbox(inboxId) {
  return ensureMediaState(inboxId);
}

export function useWavoipMedia(inboxId = null) {
  const state = inboxId ? ensureMediaState(inboxId) : null;

  const refreshDevices = async targetInboxId => {
    const mediaState = ensureMediaState(targetInboxId);
    const client = getWavoipClient(targetInboxId);
    if (!client?.getMultimediaDevices) {
      return { inputDevices: [], outputDevices: [] };
    }

    const devices = await client.getMultimediaDevices();
    mediaState.inputDevices.value = devices?.inputs || [];
    mediaState.outputDevices.value = devices?.outputs || [];
    const multimedia = client.multimedia;
    mediaState.activeInputId.value = multimedia?.inputDeviceId || null;
    mediaState.activeOutputId.value = multimedia?.outputDeviceId || null;
    return {
      inputDevices: mediaState.inputDevices.value,
      outputDevices: mediaState.outputDevices.value,
    };
  };

  const setInputDevice = async (targetInboxId, deviceId) => {
    const client = getWavoipClient(targetInboxId);
    if (!client?.multimedia?.setInputDevice) return false;
    await client.multimedia.setInputDevice(deviceId);
    ensureMediaState(targetInboxId).activeInputId.value = deviceId;
    return true;
  };

  const setOutputDevice = async (targetInboxId, deviceId) => {
    const client = getWavoipClient(targetInboxId);
    if (!client?.multimedia?.setOutputDevice) return false;
    await client.multimedia.setOutputDevice(deviceId);
    ensureMediaState(targetInboxId).activeOutputId.value = deviceId;
    return true;
  };

  if (state) {
    return {
      inputDevices: readonly(state.inputDevices),
      outputDevices: readonly(state.outputDevices),
      activeInputId: readonly(state.activeInputId),
      activeOutputId: readonly(state.activeOutputId),
      refreshDevices,
      setInputDevice,
      setOutputDevice,
    };
  }

  return {
    refreshDevices,
    setInputDevice,
    setOutputDevice,
    getWavoipMediaForInbox,
  };
}
