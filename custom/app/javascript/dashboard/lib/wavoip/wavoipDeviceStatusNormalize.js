const STATUS_ALIASES = {
  connected: 'open',
  disconnected: 'close',
};

export function normalizeWavoipDeviceStatus(status) {
  if (!status) return status;
  const key = String(status);
  return STATUS_ALIASES[key] || STATUS_ALIASES[key.toLowerCase()] || status;
}
