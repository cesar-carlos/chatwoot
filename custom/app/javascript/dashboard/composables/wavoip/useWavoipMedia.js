import { readonly, ref } from 'vue';
import { getWavoipClient } from 'customDashboard/lib/wavoip/wavoipClientRegistry';
import {
  applyWavoipInputDevice,
  applyWavoipOutputDevice,
  normalizeWavoipMultimediaDevices,
  readActiveMultimediaIds,
} from 'customDashboard/lib/wavoip/wavoipMultimedia';

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

export function clearWavoipMediaForInbox(inboxId) {
  mediaByInbox.delete(inboxId);
}

export function useWavoipMedia(inboxId = null) {
  const state = inboxId ? ensureMediaState(inboxId) : null;

  const refreshDevices = async targetInboxId => {
    const mediaState = ensureMediaState(targetInboxId);
    const client = getWavoipClient(targetInboxId);
    if (!client?.getMultimediaDevices) {
      return { inputDevices: [], outputDevices: [] };
    }

    const devices = await Promise.resolve(client.getMultimediaDevices());
    const { inputs, outputs } = normalizeWavoipMultimediaDevices(devices);
    mediaState.inputDevices.value = inputs;
    mediaState.outputDevices.value = outputs;
    const { inputId, outputId } = readActiveMultimediaIds(client.multimedia);
    mediaState.activeInputId.value = inputId;
    mediaState.activeOutputId.value = outputId;
    return {
      inputDevices: mediaState.inputDevices.value,
      outputDevices: mediaState.outputDevices.value,
    };
  };

  const setInputDevice = async (targetInboxId, deviceId) => {
    const client = getWavoipClient(targetInboxId);
    const applied = await applyWavoipInputDevice(client?.multimedia, deviceId);
    if (!applied) return false;
    ensureMediaState(targetInboxId).activeInputId.value = deviceId;
    return true;
  };

  const setOutputDevice = async (targetInboxId, deviceId) => {
    const client = getWavoipClient(targetInboxId);
    const applied = await applyWavoipOutputDevice(client?.multimedia, deviceId);
    if (!applied) return false;
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
