import { describe, expect, it } from 'vitest';
import {
  messageCreatedAt,
  normalizeStoreMessage,
} from 'dashboard/store/modules/conversations/helpers';

describe('conversation message store helpers', () => {
  describe('messageCreatedAt', () => {
    it('reads snake_case timestamps', () => {
      expect(
        messageCreatedAt({ created_at: '2024-01-01T11:00:00Z' })
      ).toBe(new Date('2024-01-01T11:00:00Z').getTime());
    });

    it('reads camelCase timestamps', () => {
      expect(messageCreatedAt({ createdAt: '2024-01-01T11:00:00Z' })).toBe(
        new Date('2024-01-01T11:00:00Z').getTime()
      );
    });
  });

  describe('normalizeStoreMessage', () => {
    it('converts camelCase keys to snake_case', () => {
      expect(
        normalizeStoreMessage({
          id: 1,
          createdAt: '2024-01-01T11:00:00Z',
          contentAttributes: { deleted: false },
        })
      ).toEqual({
        id: 1,
        created_at: '2024-01-01T11:00:00Z',
        content_attributes: { deleted: false },
      });
    });
  });
});
