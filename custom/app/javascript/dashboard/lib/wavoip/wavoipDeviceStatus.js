import { readonly, ref } from 'vue';

const statusByInbox = new Map();

const ensureEntry = inboxId => {
  if (!statusByInbox.has(inboxId)) {
    statusByInbox.set(inboxId, {
      whatsAppStatus: ref(null),
      connectionStatus: ref(null),
      isRestricted: ref(false),
      restrictedUntil: ref(null),
      activeCalls: ref(0),
      numChannels: ref(null),
    });
  }
  return statusByInbox.get(inboxId);
};

export function getWavoipDeviceStatus(inboxId) {
  return ensureEntry(inboxId);
}

export function setWavoipWhatsAppStatus(inboxId, status) {
  ensureEntry(inboxId).whatsAppStatus.value = status;
}

export function setWavoipConnectionStatus(inboxId, status) {
  ensureEntry(inboxId).connectionStatus.value = status;
}

export function setWavoipRestricted(
  inboxId,
  restricted,
  restrictedUntil = null
) {
  const entry = ensureEntry(inboxId);
  entry.isRestricted.value = restricted;
  entry.restrictedUntil.value = restrictedUntil;
}

export function setWavoipActiveCalls(inboxId, count) {
  ensureEntry(inboxId).activeCalls.value = Math.max(0, Number(count) || 0);
}

export function setWavoipNumChannels(inboxId, count) {
  const entry = ensureEntry(inboxId);
  const parsed = Number(count);
  entry.numChannels.value =
    Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

export function isWavoipDeviceAtChannelCapacity(inboxId) {
  const entry = ensureEntry(inboxId);
  const channels = entry.numChannels.value;
  if (!channels) return false;
  return entry.activeCalls.value >= channels;
}

export function hasWavoipDeviceActiveCalls(inboxId) {
  return ensureEntry(inboxId).activeCalls.value > 0;
}

export function clearWavoipDeviceStatus(inboxId) {
  statusByInbox.delete(inboxId);
}

/** True when the SDK reported WebSocket `disconnected` for this inbox. */
export function isWavoipWebSocketDisconnected(inboxId) {
  if (!inboxId) return false;
  return ensureEntry(inboxId).connectionStatus.value === 'disconnected';
}

/**
 * WebSocket is usable for offer/accept. `null` means status not reported yet
 * (treat as ok right after connect before the first event).
 */
export function isWavoipWebSocketReady(inboxId) {
  if (!inboxId) return false;
  const status = ensureEntry(inboxId).connectionStatus.value;
  return status === 'connected' || status == null;
}

export function useWavoipDeviceStatus(inboxId) {
  const entry = ensureEntry(inboxId);
  return {
    whatsAppStatus: readonly(entry.whatsAppStatus),
    connectionStatus: readonly(entry.connectionStatus),
    isRestricted: readonly(entry.isRestricted),
    restrictedUntil: readonly(entry.restrictedUntil),
    activeCalls: readonly(entry.activeCalls),
    numChannels: readonly(entry.numChannels),
  };
}
