import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  recordWavoipOutboundVolume,
  wavoipOutboundVolumeToastKey,
  WAVOIP_OUTBOUND_VOLUME_SOFT,
  WAVOIP_OUTBOUND_VOLUME_ELEVATED,
} from '../wavoipOutboundVolume';

describe('wavoipOutboundVolume', () => {
  let store;

  beforeEach(() => {
    store = new Map();
  });

  const fakeStorage = {
    getItem: key => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, String(value)),
  };

  it('returns none below soft threshold', () => {
    expect(recordWavoipOutboundVolume(1, fakeStorage)).toBe('none');
  });

  it('returns soft exactly at soft threshold', () => {
    for (let i = 0; i < WAVOIP_OUTBOUND_VOLUME_SOFT - 1; i += 1) {
      recordWavoipOutboundVolume(1, fakeStorage);
    }
    expect(recordWavoipOutboundVolume(1, fakeStorage)).toBe('soft');
  });

  it('returns elevated exactly at elevated threshold', () => {
    for (let i = 0; i < WAVOIP_OUTBOUND_VOLUME_ELEVATED - 1; i += 1) {
      recordWavoipOutboundVolume(1, fakeStorage);
    }
    expect(recordWavoipOutboundVolume(1, fakeStorage)).toBe('elevated');
  });

  it('maps levels to i18n keys', () => {
    expect(wavoipOutboundVolumeToastKey('soft')).toBe(
      'CONVERSATION.WAVOIP_CALL.OUTBOUND_VOLUME_SOFT'
    );
    expect(wavoipOutboundVolumeToastKey('elevated')).toBe(
      'CONVERSATION.WAVOIP_CALL.OUTBOUND_VOLUME_ELEVATED'
    );
    expect(wavoipOutboundVolumeToastKey('none')).toBeNull();
  });
});
