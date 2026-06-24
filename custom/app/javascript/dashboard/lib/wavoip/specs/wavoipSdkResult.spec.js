import { describe, expect, it, vi } from 'vitest';
import {
  formatWavoipStartCallError,
  unwrapWavoipSdkResult,
} from '../wavoipSdkResult';

describe('wavoipSdkResult', () => {
  it('unwraps { call, err } shape', () => {
    const call = { id: 'c1', end: vi.fn() };
    expect(unwrapWavoipSdkResult({ call, err: null })).toEqual({
      call,
      err: null,
    });
  });

  it('unwraps legacy direct call object', () => {
    const call = { id: 'c2', mute: vi.fn() };
    expect(unwrapWavoipSdkResult(call)).toEqual({ call, err: null });
  });

  it('unwraps pairingCode result shape', () => {
    expect(unwrapWavoipSdkResult({ pairingCode: '1234-5678', err: null }, 'pairingCode')).toEqual({
      pairingCode: '1234-5678',
      err: null,
    });
  });

  it('formats device-specific startCall errors', () => {
    const t = vi.fn((key, params) => `${key}:${params?.detail || ''}`);
    const message = formatWavoipStartCallError(
      { devices: [{ token: 'tok', reason: 'offline' }] },
      t
    );
    expect(message).toContain('offline');
    expect(t).toHaveBeenCalledWith(
      'CONVERSATION.WAVOIP_CALL.START_CALL_DEVICE_FAILED',
      { detail: 'offline' }
    );
  });
});
