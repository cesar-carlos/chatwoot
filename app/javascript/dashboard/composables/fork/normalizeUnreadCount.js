// FORK: extracted for merge-safe fork integration
export const CONVERSATION_UNREAD_BADGE_CAP = 9;

export const normalizeUnreadCount = raw => {
  const parsedCount = Number(raw);
  if (Number.isNaN(parsedCount) || parsedCount <= 0) {
    return 0;
  }

  return Math.floor(parsedCount);
};

export const formatConversationUnreadBadgeLabel = count => {
  const normalizedCount = normalizeUnreadCount(count);
  if (normalizedCount === 0) return '';

  return normalizedCount > CONVERSATION_UNREAD_BADGE_CAP
    ? `${CONVERSATION_UNREAD_BADGE_CAP}+`
    : String(normalizedCount);
};
