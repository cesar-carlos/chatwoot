const STATUS_ALIASES = {
  connected: 'open',
  disconnected: 'close',
};

export function normalizeWavoipDeviceStatus(status) {
  if (!status) return status;
  return STATUS_ALIASES[status] || status;
}
