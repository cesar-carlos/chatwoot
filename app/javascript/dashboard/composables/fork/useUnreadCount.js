// FORK: extracted for merge-safe fork integration
import { computed, unref } from 'vue';
import { normalizeUnreadCount } from './normalizeUnreadCount';

export const useUnreadCount = conversationSource => {
  const unreadCount = computed(() => {
    const conversation = unref(conversationSource);
    const rawUnreadCount =
      conversation?.unreadCount ?? conversation?.unread_count;

    return normalizeUnreadCount(rawUnreadCount);
  });

  const hasUnread = computed(() => unreadCount.value > 0);

  return { unreadCount, hasUnread };
};
