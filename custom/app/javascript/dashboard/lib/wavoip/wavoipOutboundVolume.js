/** Soft outbound volume counters (localStorage) for agent toast at 20 / 50. */
export const WAVOIP_OUTBOUND_VOLUME_SOFT = 20;
export const WAVOIP_OUTBOUND_VOLUME_ELEVATED = 50;

const storageKey = (accountId, dateKey) =>
  `wavoip:outbound_volume:${accountId}:${dateKey}`;

const todayKey = () => new Date().toISOString().slice(0, 10);

/**
 * Increment today's outbound startCall count for the account and return the
 * warn level when a threshold is crossed exactly (so toast fires once).
 * @returns {'none'|'soft'|'elevated'}
 */
export function recordWavoipOutboundVolume(accountId, storage = localStorage) {
  if (accountId == null || accountId === '') return 'none';

  const key = storageKey(accountId, todayKey());
  let count = 0;
  try {
    count = Number(storage.getItem(key) || 0) + 1;
    storage.setItem(key, String(count));
  } catch {
    return 'none';
  }

  if (count === WAVOIP_OUTBOUND_VOLUME_ELEVATED) return 'elevated';
  if (count === WAVOIP_OUTBOUND_VOLUME_SOFT) return 'soft';
  return 'none';
}

export function wavoipOutboundVolumeToastKey(level) {
  if (level === 'elevated') {
    return 'CONVERSATION.WAVOIP_CALL.OUTBOUND_VOLUME_ELEVATED';
  }
  if (level === 'soft') {
    return 'CONVERSATION.WAVOIP_CALL.OUTBOUND_VOLUME_SOFT';
  }
  return null;
}
