// FORK: WhatsApp-like message forward (pseudo-forward inside Chatwoot)
import ContactAPI from 'dashboard/api/contacts';
import ConversationApi from 'dashboard/api/conversations';
import MessageApi from 'dashboard/api/inbox/message';
import { createPendingMessage } from 'dashboard/helper/commons';
import getUuid from 'widget/helpers/uuid';

export const FORWARD_PROVIDERS = ['evolution_go', 'evolution'];
export const MAX_FORWARD_DESTINATIONS = 5;
export const MAX_RECENT_CONVERSATIONS = 10;

export function inboxSupportsForward(inbox) {
  if (!inbox || inbox.channel_type !== 'Channel::Whatsapp') return false;
  return FORWARD_PROVIDERS.includes(inbox.provider);
}

export function messageCanBeForwarded(message) {
  if (!message) return false;
  const content = message.content || '';
  const attachments = message.attachments || [];
  return Boolean(content) || (Array.isArray(attachments) && attachments.length > 0);
}

function attachmentUrl(attachment) {
  return (
    attachment?.data_url ||
    attachment?.dataUrl ||
    attachment?.download_url ||
    attachment?.downloadUrl ||
    attachment?.file_url ||
    attachment?.fileUrl ||
    ''
  );
}

function attachmentFileName(attachment, index) {
  const fromUrl = attachmentUrl(attachment).split('?')[0].split('/').pop();
  if (fromUrl && fromUrl.includes('.')) return decodeURIComponent(fromUrl);
  const type = attachment?.file_type || attachment?.fileType || 'file';
  return `attachment-${index + 1}.${type === 'image' ? 'jpg' : 'bin'}`;
}

export async function fetchAttachmentFiles(attachments = []) {
  const files = [];
  const list = Array.isArray(attachments) ? attachments : [];

  for (let i = 0; i < list.length; i += 1) {
    const attachment = list[i];
    const url = attachmentUrl(attachment);
    if (!url) continue;

    const response = await fetch(url, { credentials: 'same-origin' });
    if (!response.ok) {
      throw new Error(`Failed to download attachment (${response.status})`);
    }
    const blob = await response.blob();
    const type =
      blob.type ||
      attachment?.content_type ||
      attachment?.contentType ||
      'application/octet-stream';
    files.push(
      new File([blob], attachmentFileName(attachment, i), { type })
    );
  }

  return files;
}

export function buildForwardContentAttributes(sourceMessage) {
  return {
    forwarded: true,
    forwarded_from_message_id: sourceMessage.id,
    forwarded_from_conversation_id:
      sourceMessage.conversation_id || sourceMessage.conversationId,
  };
}

export function recentConversationsForInbox(conversations, inboxId, excludeConversationId) {
  if (!Array.isArray(conversations) || !inboxId) return [];

  return conversations
    .filter(conversation => {
      const convInboxId = conversation.inbox_id ?? conversation.inboxId;
      const id = conversation.id;
      if (Number(convInboxId) !== Number(inboxId)) return false;
      if (excludeConversationId && Number(id) === Number(excludeConversationId)) {
        return false;
      }
      return true;
    })
    .slice(0, MAX_RECENT_CONVERSATIONS)
    .map(conversation => {
      const meta = conversation.meta || {};
      const sender = meta.sender || {};
      return {
        key: `conversation:${conversation.id}`,
        conversationId: conversation.id,
        contactId: sender.id || conversation.meta?.sender?.id,
        label: sender.name || `#${conversation.id}`,
        phoneNumber: sender.phone_number || sender.phoneNumber || '',
        thumbnail: sender.thumbnail || '',
        kind: 'conversation',
      };
    });
}

async function findConversationForContact(contactId, inboxId) {
  const { data } = await ContactAPI.getConversations(contactId, { inboxId });
  const payload = data?.payload || data || [];
  const list = Array.isArray(payload) ? payload : [];
  const forInbox = list.filter(
    conversation => Number(conversation.inbox_id) === Number(inboxId)
  );
  const open = forInbox.find(conversation => conversation.status === 'open');
  return open || forInbox[0] || null;
}

async function createConversationForContact({
  contactId,
  inboxId,
  assigneeId,
}) {
  const { data } = await ContactAPI.getContactableInboxes(contactId);
  const inboxes = data?.payload || data || [];
  const list = Array.isArray(inboxes) ? inboxes : [];
  const match = list.find(entry => {
    const inbox = entry.inbox || entry;
    return Number(inbox.id) === Number(inboxId);
  });
  if (!match) {
    throw new Error('Contact is not reachable on this WhatsApp inbox');
  }

  const sourceId = match.source_id || match.sourceId;
  const response = await ConversationApi.create({
    inbox_id: inboxId,
    contact_id: contactId,
    source_id: sourceId,
    assignee_id: assigneeId,
  });
  return response.data;
}

export async function resolveDestinationConversationId({
  destination,
  inboxId,
  assigneeId,
}) {
  if (destination.conversationId) {
    return destination.conversationId;
  }
  if (!destination.contactId) {
    throw new Error('Destination contact is required');
  }

  const existing = await findConversationForContact(
    destination.contactId,
    inboxId
  );
  if (existing?.id) return existing.id;

  const created = await createConversationForContact({
    contactId: destination.contactId,
    inboxId,
    assigneeId,
  });
  return created.id;
}

export async function forwardMessageToDestinations({
  sourceMessage,
  destinations,
  inboxId,
  assigneeId,
  sendMessage,
}) {
  const content = sourceMessage.content || '';
  const attachments = sourceMessage.attachments || [];
  const files = await fetchAttachmentFiles(attachments);
  const contentAttributes = buildForwardContentAttributes(sourceMessage);

  const results = { succeeded: 0, failed: 0, errors: [] };

  for (const destination of destinations.slice(0, MAX_FORWARD_DESTINATIONS)) {
    try {
      const conversationId = await resolveDestinationConversationId({
        destination,
        inboxId,
        assigneeId,
      });

      const echoId = getUuid();
      const payload = {
        conversationId,
        message: content,
        private: false,
        contentAttributes,
        echo_id: echoId,
        files,
      };

      if (typeof sendMessage === 'function') {
        await sendMessage(payload);
      } else {
        await MessageApi.create(payload);
      }
      results.succeeded += 1;
    } catch (error) {
      results.failed += 1;
      results.errors.push({
        destination,
        message: error?.message || 'Forward failed',
      });
    }
  }

  return results;
}

export function createForwardPendingPayload(payload) {
  return createPendingMessage(payload);
}
