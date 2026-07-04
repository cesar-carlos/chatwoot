import { describe, expect, it } from 'vitest';
import {
  normalizeCallDirection,
  isOutboundCallDirection,
} from '../voiceCallDirection';

describe('voiceCallDirection', () => {
  describe('normalizeCallDirection', () => {
    it.each(['outbound', 'OUTBOUND', 'outgoing', 'OUTGOING'])(
      'normalizes %s to outbound',
      raw => {
        expect(normalizeCallDirection(raw)).toBe('outbound');
      }
    );

    it.each(['inbound', 'incoming', 'INCOMING', undefined, null, ''])(
      'normalizes %s to inbound',
      raw => {
        expect(normalizeCallDirection(raw)).toBe('inbound');
      }
    );
  });

  describe('isOutboundCallDirection', () => {
    it('returns true for any outbound spelling', () => {
      expect(isOutboundCallDirection('outgoing')).toBe(true);
      expect(isOutboundCallDirection('OUTBOUND')).toBe(true);
    });

    it('returns false for inbound/unknown values', () => {
      expect(isOutboundCallDirection('incoming')).toBe(false);
      expect(isOutboundCallDirection(undefined)).toBe(false);
    });
  });
});
