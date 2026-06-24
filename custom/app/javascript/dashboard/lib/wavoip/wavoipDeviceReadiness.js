export function getPrimaryDevice(client) {
  const devices = client?.getDevices?.() || [];
  return devices[0] || null;
}

export function getDeviceStatus(client) {
  return getPrimaryDevice(client)?.status ?? null;
}

const STATUS_I18N_KEYS = {
  close: 'CONVERSATION.WAVOIP_CALL.DEVICE_NOT_LINKED',
  disconnected: 'CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED',
  connecting: 'CONVERSATION.WAVOIP_CALL.DEVICE_CONNECTING',
  hibernating: 'CONVERSATION.WAVOIP_CALL.DEVICE_HIBERNATING',
  WAITING_PAYMENT: 'CONVERSATION.WAVOIP_CALL.DEVICE_WAITING_PAYMENT',
  EXTERNAL_INTEGRATION_ERROR:
    'CONVERSATION.WAVOIP_CALL.DEVICE_INTEGRATION_ERROR',
  BUILDING: 'CONVERSATION.WAVOIP_CALL.DEVICE_BUILDING',
  restarting: 'CONVERSATION.WAVOIP_CALL.DEVICE_RESTARTING',
};

export function wavoipDeviceErrorKey(status) {
  return (
    STATUS_I18N_KEYS[status] || 'CONVERSATION.WAVOIP_CALL.DEVICE_NOT_READY'
  );
}
