import {
  CONVERSATION_UNREAD_BADGE_CAP,
  formatConversationUnreadBadgeLabel,
  normalizeUnreadCount,
} from '../normalizeUnreadCount';

describe('normalizeUnreadCount', () => {
  it('returns 0 for zero, null, undefined, invalid, and negative values', () => {
    expect(normalizeUnreadCount(0)).toBe(0);
    expect(normalizeUnreadCount(null)).toBe(0);
    expect(normalizeUnreadCount(undefined)).toBe(0);
    expect(normalizeUnreadCount('abc')).toBe(0);
    expect(normalizeUnreadCount(-1)).toBe(0);
  });

  it('normalizes numeric strings and floors fractional counts', () => {
    expect(normalizeUnreadCount('3')).toBe(3);
    expect(normalizeUnreadCount(3.7)).toBe(3);
  });

  it('returns positive integers as-is', () => {
    expect(normalizeUnreadCount(9)).toBe(9);
    expect(normalizeUnreadCount(10)).toBe(10);
  });
});

describe('formatConversationUnreadBadgeLabel', () => {
  it('returns empty string for zero or invalid counts', () => {
    expect(formatConversationUnreadBadgeLabel(0)).toBe('');
    expect(formatConversationUnreadBadgeLabel(null)).toBe('');
  });

  it('returns the count as string between 1 and the cap', () => {
    expect(formatConversationUnreadBadgeLabel(1)).toBe('1');
    expect(formatConversationUnreadBadgeLabel(9)).toBe('9');
  });

  it('returns capped label above the cap', () => {
    expect(formatConversationUnreadBadgeLabel(10)).toBe('9+');
    expect(formatConversationUnreadBadgeLabel(99)).toBe('9+');
  });

  it('uses the shared cap constant', () => {
    expect(CONVERSATION_UNREAD_BADGE_CAP).toBe(9);
  });
});
