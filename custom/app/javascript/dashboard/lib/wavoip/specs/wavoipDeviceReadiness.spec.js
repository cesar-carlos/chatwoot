import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  getDeviceStatus,
  syncDeviceChannelStats,
  wakeDeviceIfNeeded,
  wavoipDeviceErrorKey,
} from '../wavoipDeviceReadiness';
import {
  getWavoipDeviceStatus,
  isWavoipDeviceAtChannelCapacity,
} from '../wavoipDeviceStatus';

vi.mock('customDashboard/lib/wavoip/wavoipDiagnosticsCollector', () => ({
  recordConnectivityIssue: vi.fn(),
}));

describe('wavoipDeviceReadiness', () => {
  beforeEach(() => {
    getWavoipDeviceStatus(99).activeCalls.value = 0;
    getWavoipDeviceStatus(99).numChannels.value = null;
  });

  it('maps disconnected status to websocket error key', () => {
    expect(wavoipDeviceErrorKey('disconnected')).toBe(
      'CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED'
    );
  });

  it('falls back to generic not-ready key', () => {
    expect(wavoipDeviceErrorKey('unknown')).toBe(
      'CONVERSATION.WAVOIP_CALL.DEVICE_NOT_READY'
    );
  });

  it('reads status from the first device', () => {
    const client = {
      getDevices: () => [{ status: 'close' }],
    };

    expect(getDeviceStatus(client)).toBe('close');
  });

  it('syncs activeCalls and num_channels into the device status store', () => {
    syncDeviceChannelStats(99, { activeCalls: 2, num_channels: 5 });

    const status = getWavoipDeviceStatus(99);
    expect(status.activeCalls.value).toBe(2);
    expect(status.numChannels.value).toBe(5);
    expect(isWavoipDeviceAtChannelCapacity(99)).toBe(false);
  });

  it('detects channel capacity from the device status store', () => {
    syncDeviceChannelStats(99, { activeCalls: 3, num_channels: 3 });
    expect(isWavoipDeviceAtChannelCapacity(99)).toBe(true);
  });

  it('wakeDeviceIfNeeded calls wakeUp when device is hibernating', async () => {
    const wakeUp = vi.fn().mockResolvedValue(undefined);
    const device = { status: 'hibernating', wakeUp };

    const result = await wakeDeviceIfNeeded(device, { inboxId: 99 });

    expect(wakeUp).toHaveBeenCalled();
    expect(result.woke).toBe(true);
  });

  it('wakeDeviceIfNeeded is a no-op when device is already open', async () => {
    const wakeUp = vi.fn();
    const device = { status: 'open', wakeUp };

    const result = await wakeDeviceIfNeeded(device, { inboxId: 99 });

    expect(wakeUp).not.toHaveBeenCalled();
    expect(result.ready).toBe(true);
  });
});
