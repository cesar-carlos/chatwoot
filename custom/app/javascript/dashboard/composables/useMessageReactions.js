// FORK: WhatsApp Evolution Go/Node message reactions helpers
import MessageApi from 'dashboard/api/inbox/message';

export const BUSINESS_ACTOR_KEY = 'user:self';
export const REACTION_PROVIDERS = ['evolution_go', 'evolution'];
export const REACTION_BLOCKED_STATUSES = ['failed', 'progress'];

export function isBusinessReaction(entry) {
  if (!entry) return false;
  if (entry.from === 'user') return true;
  const key = entry.actor_key || entry.actorKey || '';
  return key === BUSINESS_ACTOR_KEY || /^user:\d+$/.test(String(key));
}

export function buildReactionChips(reactions) {
  if (!Array.isArray(reactions) || !reactions.length) return [];

  const counts = {};
  const mine = {};
  reactions.forEach(entry => {
    const emoji = entry?.emoji || entry?.Emoji;
    if (!emoji) return;
    counts[emoji] = (counts[emoji] || 0) + 1;
    if (isBusinessReaction(entry)) mine[emoji] = true;
  });

  return Object.entries(counts).map(([emoji, count]) => ({
    emoji,
    count,
    isMine: Boolean(mine[emoji]),
  }));
}

export function inboxSupportsReactions(inbox) {
  if (!inbox || inbox.channel_type !== 'Channel::Whatsapp') return false;
  return REACTION_PROVIDERS.includes(inbox.provider);
}

export function messageCanReceiveReaction(message) {
  if (!message) return false;

  const sourceId = message.source_id || message.sourceId;
  if (!sourceId) return false;

  if (message.private) return false;

  const attrs =
    message.content_attributes || message.contentAttributes || {};
  if (attrs.deleted) return false;

  const status = message.status;
  if (status && REACTION_BLOCKED_STATUSES.includes(status)) return false;

  return true;
}

export function extractReactionErrorMessage(
  error,
  fallback = 'Could not send reaction'
) {
  const data = error?.response?.data;
  if (typeof data?.error === 'string' && data.error.trim()) return data.error;
  if (typeof data?.message === 'string' && data.message.trim()) {
    return data.message;
  }
  if (Array.isArray(data?.errors) && data.errors[0]) {
    return String(data.errors[0]);
  }
  if (typeof error?.message === 'string' && error.message.trim()) {
    return error.message;
  }
  return fallback;
}

export function applyOptimisticReaction(message, reaction, actorId = null) {
  const attrs = {
    ...(message.content_attributes || message.contentAttributes || {}),
  };
  let reactions = Array.isArray(attrs.reactions)
    ? attrs.reactions.map(entry => ({ ...entry }))
    : [];

  reactions = reactions.filter(entry => !isBusinessReaction(entry));

  const value = String(reaction || '');
  if (value && value.toLowerCase() !== 'remove') {
    reactions.push({
      emoji: value,
      from: 'user',
      actor_key: BUSINESS_ACTOR_KEY,
      actor_id: actorId,
      updated_at: new Date().toISOString(),
    });
  }

  return {
    ...message,
    content_attributes: {
      ...attrs,
      reactions,
    },
  };
}

export async function sendWhatsappReaction({
  conversationId,
  messageId,
  reaction,
}) {
  return MessageApi.evolutionGoReact(conversationId, messageId, reaction);
}
