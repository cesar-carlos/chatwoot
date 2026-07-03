import {
  setWavoipActiveCalls,
  setWavoipNumChannels,
} from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { recordConnectivityIssue } from 'customDashboard/lib/wavoip/wavoipDiagnosticsCollector';

export function getPrimaryDevice(client) {
  const devices = client?.getDevices?.() || [];
  return devices[0] || null;
}

export function getDeviceStatus(client) {
  return getPrimaryDevice(client)?.status ?? null;
}

export function syncDeviceChannelStats(inboxId, device) {
  if (!inboxId || !device) return;

  setWavoipActiveCalls(inboxId, device.activeCalls ?? 0);

  const channels = device.num_channels ?? device.numChannels;
  if (channels != null) {
    setWavoipNumChannels(inboxId, channels);
  }
}

export async function wakeDeviceIfNeeded(device, { inboxId } = {}) {
  if (!device) {
    return { ready: false, status: null, woke: false };
  }

  if (device.status === 'open') {
    return { ready: true, status: device.status, woke: false };
  }

  if (device.status !== 'hibernating') {
    return { ready: false, status: device.status, woke: false };
  }

  try {
    await device.wakeUp?.();
    return {
      ready: device.status === 'open',
      status: device.status,
      woke: true,
    };
  } catch (error) {
    if (inboxId) {
      recordConnectivityIssue(
        inboxId,
        null,
        `wakeUp failed: ${error?.message || 'unknown error'}`
      );
    }
    return {
      ready: false,
      status: device.status,
      woke: false,
      error,
    };
  }
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
