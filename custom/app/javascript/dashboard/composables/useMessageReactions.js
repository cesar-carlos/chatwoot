// FORK: WhatsApp Evolution Go/Node message reactions helpers
import MessageApi from 'dashboard/api/inbox/message';

export const BUSINESS_ACTOR_KEY = 'user:self';
export const REACTION_PROVIDERS = ['evolution_go', 'evolution'];

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
