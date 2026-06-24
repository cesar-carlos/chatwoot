import { readonly, ref } from 'vue';

const statusByInbox = new Map();

const ensureEntry = inboxId => {
  if (!statusByInbox.has(inboxId)) {
    statusByInbox.set(inboxId, {
      whatsAppStatus: ref(null),
      connectionStatus: ref(null),
      isRestricted: ref(false),
      restrictedUntil: ref(null),
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

export function clearWavoipDeviceStatus(inboxId) {
  statusByInbox.delete(inboxId);
}

export function useWavoipDeviceStatus(inboxId) {
  const entry = ensureEntry(inboxId);
  return {
    whatsAppStatus: readonly(entry.whatsAppStatus),
    connectionStatus: readonly(entry.connectionStatus),
    isRestricted: readonly(entry.isRestricted),
    restrictedUntil: readonly(entry.restrictedUntil),
  };
}
