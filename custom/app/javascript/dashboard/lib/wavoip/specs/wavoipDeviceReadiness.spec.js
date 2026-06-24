import { describe, expect, it } from 'vitest';
import {
  getDeviceStatus,
  wavoipDeviceErrorKey,
} from '../wavoipDeviceReadiness';

describe('wavoipDeviceReadiness', () => {
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
});
