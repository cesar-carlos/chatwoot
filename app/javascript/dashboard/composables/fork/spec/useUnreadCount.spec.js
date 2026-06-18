import { ref } from 'vue';
import { useUnreadCount } from '../useUnreadCount';

describe('useUnreadCount', () => {
  const buildUnread = (conversation = {}) => {
    const source = ref(conversation);
    return { ...useUnreadCount(source), source };
  };

  it('returns 0 when unread_count is 0', () => {
    const { unreadCount, hasUnread } = buildUnread({ unread_count: 0 });
    expect(unreadCount.value).toBe(0);
    expect(hasUnread.value).toBe(false);
  });

  it('reads unread_count from snake_case field', () => {
    const { unreadCount, hasUnread } = buildUnread({ unread_count: 3 });
    expect(unreadCount.value).toBe(3);
    expect(hasUnread.value).toBe(true);
  });

  it('prefers unreadCount camelCase over unread_count', () => {
    const { unreadCount } = buildUnread({
      unreadCount: 5,
      unread_count: 2,
    });
    expect(unreadCount.value).toBe(5);
  });

  it('returns 0 for null, undefined, and invalid values', () => {
    expect(buildUnread({ unread_count: null }).unreadCount.value).toBe(0);
    expect(buildUnread({ unread_count: undefined }).unreadCount.value).toBe(0);
    expect(buildUnread({ unread_count: 'abc' }).unreadCount.value).toBe(0);
    expect(buildUnread({ unread_count: -1 }).unreadCount.value).toBe(0);
  });

  it('normalizes numeric strings and floors fractional counts', () => {
    expect(buildUnread({ unread_count: '3' }).unreadCount.value).toBe(3);
    expect(buildUnread({ unread_count: 3.7 }).unreadCount.value).toBe(3);
  });

  it('keeps high counts for badge label formatting downstream', () => {
    const { unreadCount, hasUnread } = buildUnread({ unread_count: 10 });
    expect(unreadCount.value).toBe(10);
    expect(hasUnread.value).toBe(true);
  });
});
