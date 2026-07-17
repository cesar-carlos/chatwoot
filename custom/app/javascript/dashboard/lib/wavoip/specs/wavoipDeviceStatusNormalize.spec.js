import { describe, expect, it } from 'vitest';
import { normalizeWavoipDeviceStatus } from '../wavoipDeviceStatusNormalize';

describe('normalizeWavoipDeviceStatus', () => {
  it('maps future Wavoip aliases to canonical statuses', () => {
    expect(normalizeWavoipDeviceStatus('connected')).toBe('open');
    expect(normalizeWavoipDeviceStatus('disconnected')).toBe('close');
    expect(normalizeWavoipDeviceStatus('Connected')).toBe('open');
  });

  it('leaves known statuses unchanged', () => {
    expect(normalizeWavoipDeviceStatus('open')).toBe('open');
    expect(normalizeWavoipDeviceStatus('BUILDING')).toBe('BUILDING');
  });
});
