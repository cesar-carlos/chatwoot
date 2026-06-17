// FORK: extracted for merge-safe fork integration
import { computed, unref } from 'vue';

export const useUnreadCount = conversationSource => {
  const unreadCount = computed(() => {
    const conversation = unref(conversationSource);
    const rawUnreadCount =
      conversation?.unreadCount ?? conversation?.unread_count;
    const parsedUnreadCount = Number(rawUnreadCount);
    if (Number.isNaN(parsedUnreadCount) || parsedUnreadCount <= 0) {
      return 0;
    }

    return Math.floor(parsedUnreadCount);
  });

  const hasUnread = computed(() => unreadCount.value > 0);

  return { unreadCount, hasUnread };
};
