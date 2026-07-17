// FORK: WhatsApp-like message forward (pseudo-forward inside Chatwoot)
import ContactAPI from 'dashboard/api/contacts';
import ConversationApi from 'dashboard/api/conversations';
import MessageApi from 'dashboard/api/inbox/message';
import { createPendingMessage } from 'dashboard/helper/commons';
import getUuid from 'widget/helpers/uuid';

export const FORWARD_PROVIDERS = ['evolution_go', 'evolution'];
export const MAX_FORWARD_DESTINATIONS = 5;
export const MAX_RECENT_CONVERSATIONS = 10;
export const FORWARDABLE_FILE_TYPES = ['image', 'audio', 'video', 'file'];

export function inboxSupportsForward(inbox) {
  if (!inbox || inbox.channel_type !== 'Channel::Whatsapp') return false;
  return FORWARD_PROVIDERS.includes(inbox.provider);
}

function attachmentFileType(attachment) {
  return attachment?.file_type || attachment?.fileType || '';
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

export function isDownloadableAttachment(attachment) {
  if (!attachment) return false;
  if (!FORWARDABLE_FILE_TYPES.includes(attachmentFileType(attachment))) {
    return false;
  }
  return Boolean(attachmentUrl(attachment));
}

export function getForwardableAttachments(message) {
  const list = Array.isArray(message?.attachments) ? message.attachments : [];
  return list.filter(isDownloadableAttachment);
}

export function messageCanBeForwarded(message) {
  if (!message) return false;
  const content = (message.content || '').trim();
  return Boolean(content) || getForwardableAttachments(message).length > 0;
}

function attachmentFileName(attachment, index) {
  const explicit =
    attachment?.filename ||
    attachment?.file_name ||
    attachment?.fileName ||
    attachment?.fallback_title ||
    attachment?.fallbackTitle ||
    '';
  if (explicit) return explicit;

  const fromUrl = attachmentUrl(attachment).split('?')[0].split('/').pop();
  if (fromUrl && fromUrl.includes('.')) return decodeURIComponent(fromUrl);

  const type = attachmentFileType(attachment) || 'file';
  const extension =
    type === 'image' ? 'jpg' : type === 'audio' ? 'ogg' : type === 'video' ? 'mp4' : 'bin';
  return `attachment-${index + 1}.${extension}`;
}

export function extractErrorMessage(error, fallback = 'Forward failed') {
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

export async function fetchAttachmentFiles(attachments = []) {
  const files = [];
  const list = Array.isArray(attachments) ? attachments : [];

  for (let i = 0; i < list.length; i += 1) {
    const attachment = list[i];
    if (!FORWARDABLE_FILE_TYPES.includes(attachmentFileType(attachment))) {
      continue;
    }

    const url = attachmentUrl(attachment);
    if (!url) {
      throw new Error('Attachment URL is missing');
    }

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
    files.push(new File([blob], attachmentFileName(attachment, i), { type }));
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

export function isSameDestination(a, b) {
  if (!a || !b) return false;
  if (
    a.conversationId &&
    b.conversationId &&
    Number(a.conversationId) === Number(b.conversationId)
  ) {
    return true;
  }
  if (
    a.contactId &&
    b.contactId &&
    Number(a.contactId) === Number(b.contactId)
  ) {
    return true;
  }
  return false;
}

export function dedupeDestinations(destinations = []) {
  const unique = [];
  destinations.forEach(destination => {
    if (unique.some(item => isSameDestination(item, destination))) return;
    unique.push(destination);
  });
  return unique;
}

export function recentConversationsForInbox(
  conversations,
  inboxId,
  excludeConversationId
) {
  if (!Array.isArray(conversations) || !inboxId) return [];

  return conversations
    .filter(conversation => {
      const convInboxId = conversation.inbox_id ?? conversation.inboxId;
      const id = conversation.id;
      if (Number(convInboxId) !== Number(inboxId)) return false;
      if (
        excludeConversationId &&
        Number(id) === Number(excludeConversationId)
      ) {
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

function contactableInboxList(data) {
  const payload = data?.payload || data || [];
  return Array.isArray(payload) ? payload : [];
}

export function contactIsReachableOnInbox(contactablePayload, inboxId) {
  return contactableInboxList(contactablePayload).some(entry => {
    const inbox = entry.inbox || entry;
    return Number(inbox.id) === Number(inboxId);
  });
}

export async function filterContactsReachableOnInbox(contacts, inboxId) {
  if (!inboxId || !Array.isArray(contacts) || !contacts.length) return [];

  const checks = await Promise.all(
    contacts.map(async contact => {
      try {
        const { data } = await ContactAPI.getContactableInboxes(contact.id);
        if (!contactIsReachableOnInbox(data, inboxId)) return null;
        return contact;
      } catch {
        return null;
      }
    })
  );

  return checks.filter(Boolean);
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
  const list = contactableInboxList(data);
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
  contentOverride,
}) {
  const content =
    typeof contentOverride === 'string'
      ? contentOverride
      : sourceMessage.content || '';
  const attachments = getForwardableAttachments(sourceMessage);
  const files = await fetchAttachmentFiles(attachments);

  if (!content.trim() && files.length === 0) {
    throw new Error('Nothing to forward');
  }

  const contentAttributes = buildForwardContentAttributes(sourceMessage);
  const uniqueDestinations = dedupeDestinations(destinations).slice(
    0,
    MAX_FORWARD_DESTINATIONS
  );

  const results = { succeeded: 0, failed: 0, errors: [], failedDestinations: [] };

  for (const destination of uniqueDestinations) {
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
      results.failedDestinations.push(destination);
      results.errors.push({
        destination,
        message: extractErrorMessage(error),
      });
    }
  }

  return results;
}

export function createForwardPendingPayload(payload) {
  return createPendingMessage(payload);
}
