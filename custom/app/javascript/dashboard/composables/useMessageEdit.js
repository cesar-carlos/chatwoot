// FORK: Evolution Go agent edit → WhatsApp (sync_edit_to_whatsapp)
import MessageApi from 'dashboard/api/inbox/message';
import { MESSAGE_TYPE } from 'shared/constants/messages';

export const EDIT_PROVIDERS = ['evolution_go'];
export const EDITED_PREFIX = 'Edited message:\n\n';
export const MAX_EDIT_LENGTH = 4096;

export function inboxSupportsMessageEdit(inbox) {
  if (!inbox || inbox.channel_type !== 'Channel::Whatsapp') return false;
  if (!EDIT_PROVIDERS.includes(inbox.provider)) return false;

  // Admins get full provider_config; agents get top-level sync_edit_to_whatsapp only.
  const config = inbox.provider_config || inbox.providerConfig || {};
  return (
    config.sync_edit_to_whatsapp === true ||
    inbox.sync_edit_to_whatsapp === true
  );
}

export function stripEditedPrefix(content = '') {
  const text = String(content || '');
  return text.startsWith(EDITED_PREFIX)
    ? text.slice(EDITED_PREFIX.length)
    : text;
}

export function messageCanBeEdited(message) {
  if (!message) return false;

  const messageType = message.message_type ?? message.messageType;
  const isOutgoing =
    messageType === MESSAGE_TYPE.OUTGOING || messageType === 'outgoing';
  if (!isOutgoing) return false;

  if (message.private) return false;

  const sourceId = message.source_id || message.sourceId;
  if (!sourceId) return false;

  const attrs = message.content_attributes || message.contentAttributes || {};
  if (attrs.deleted) return false;

  // Text messages and media captions (content + attachments) are editable.
  // Attachment-only messages have no WhatsApp text body to edit.
  const bare = stripEditedPrefix(message.content || '').trim();
  return Boolean(bare);
}

export async function editEvolutionGoMessage({
  conversationId,
  messageId,
  content,
}) {
  return MessageApi.evolutionGoEdit(conversationId, messageId, content);
}
