// FORK: WhatsApp-like message forward (pseudo-forward inside Chatwoot)
import ContactAPI from 'dashboard/api/contacts';
import ConversationApi from 'dashboard/api/conversations';
import MessageApi from 'dashboard/api/inbox/message';
import { toSameOriginActiveStorageUrl } from 'customDashboard/helper/sameOriginActiveStorageUrl';
import getUuid from 'widget/helpers/uuid';

export const FORWARD_PROVIDERS = ['evolution_go', 'evolution'];
export const MAX_FORWARD_DESTINATIONS = 5;
export const MAX_FORWARD_MESSAGES = 10;
export const MAX_RECENT_CONVERSATIONS = 10;
export const MAX_CONTACTABLE_CHECKS = 20;
export const FORWARDABLE_FILE_TYPES = ['image', 'audio', 'video', 'file'];
export const FORWARD_ERROR_CODES = {
  ATTACHMENT_URL_MISSING: 'ATTACHMENT_URL_MISSING',
  ATTACHMENT_DOWNLOAD_FAILED: 'ATTACHMENT_DOWNLOAD_FAILED',
  CONTACT_NOT_REACHABLE: 'CONTACT_NOT_REACHABLE',
  DESTINATION_CONTACT_REQUIRED: 'DESTINATION_CONTACT_REQUIRED',
  NOTHING_TO_FORWARD: 'NOTHING_TO_FORWARD',
};

export class ForwardError extends Error {
  constructor(code, details = {}) {
    super(code);
    this.name = 'ForwardError';
    this.code = code;
    this.details = details;
  }
}

export function isForwardErrorCode(code) {
  return Object.values(FORWARD_ERROR_CODES).includes(code);
}

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
  const extensionByType = { image: 'jpg', audio: 'ogg', video: 'mp4' };
  const extension = extensionByType[type] || 'bin';
  return `attachment-${index + 1}.${extension}`;
}

export function extractErrorMessage(error) {
  const data = error?.response?.data;
  if (typeof data?.error === 'string' && data.error.trim()) return data.error;
  if (typeof data?.message === 'string' && data.message.trim()) {
    return data.message;
  }
  if (Array.isArray(data?.errors) && data.errors[0]) {
    return String(data.errors[0]);
  }
  if (isForwardErrorCode(error?.code)) return '';
  if (typeof error?.message === 'string' && error.message.trim()) {
    return error.message;
  }
  return '';
}

export function describeForwardError(error) {
  const code = isForwardErrorCode(error?.code) ? error.code : undefined;
  return {
    code,
    details: code ? error.details || {} : undefined,
    message: extractErrorMessage(error),
  };
}

async function downloadAttachmentFile(attachment, index) {
  const url = toSameOriginActiveStorageUrl(attachmentUrl(attachment));
  if (!url) {
    throw new ForwardError(FORWARD_ERROR_CODES.ATTACHMENT_URL_MISSING);
  }

  const response = await fetch(url, { credentials: 'same-origin' });
  if (!response.ok) {
    throw new ForwardError(FORWARD_ERROR_CODES.ATTACHMENT_DOWNLOAD_FAILED, {
      status: response.status,
    });
  }
  const blob = await response.blob();
  const type =
    blob.type ||
    attachment?.content_type ||
    attachment?.contentType ||
    'application/octet-stream';
  return new File([blob], attachmentFileName(attachment, index), { type });
}

export async function fetchAttachmentFiles(attachments = []) {
  const list = (Array.isArray(attachments) ? attachments : []).filter(
    attachment =>
      FORWARDABLE_FILE_TYPES.includes(attachmentFileType(attachment))
  );

  const files = [];
  await list.reduce(async (previous, attachment, index) => {
    await previous;
    files.push(await downloadAttachmentFile(attachment, index));
  }, Promise.resolve());

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
    .sort((a, b) => {
      const ta = Number(a.last_activity_at ?? a.lastActivityAt ?? 0);
      const tb = Number(b.last_activity_at ?? b.lastActivityAt ?? 0);
      return tb - ta;
    })
    .slice(0, MAX_RECENT_CONVERSATIONS)
    .map(conversation => {
      const meta = conversation.meta || {};
      const sender = meta.sender || {};
      const contactId = sender.id || conversation.meta?.sender?.id;
      if (!contactId) return null;

      return {
        key: `conversation:${conversation.id}`,
        conversationId: conversation.id,
        contactId,
        label: sender.name || `#${conversation.id}`,
        phoneNumber: sender.phone_number || sender.phoneNumber || '',
        thumbnail: sender.thumbnail || '',
        kind: 'conversation',
        conversationStatus: conversation.status || null,
      };
    })
    .filter(Boolean);
}

export function isWhatsAppGroupContact(contact) {
  if (!contact) return false;
  const attrs =
    contact.additionalAttributes || contact.additional_attributes || {};
  if (attrs.isWhatsappGroup || attrs.is_whatsapp_group) return true;
  const identifier = (contact.identifier || '').toString();
  return identifier.endsWith('@g.us');
}

export function isForwardSearchEligibleContact(contact) {
  return Boolean(
    contact?.phoneNumber ||
      contact?.phone_number ||
      isWhatsAppGroupContact(contact)
  );
}

export function conversationIdForContactInInbox(
  conversations,
  contactId,
  inboxId
) {
  if (!Array.isArray(conversations) || !contactId || !inboxId) return null;

  const match = conversations.find(conversation => {
    const convInboxId = conversation.inbox_id ?? conversation.inboxId;
    const senderId = conversation.meta?.sender?.id;
    return (
      Number(convInboxId) === Number(inboxId) &&
      Number(senderId) === Number(contactId)
    );
  });
  return match?.id || null;
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

export async function filterContactsReachableOnInbox(
  contacts,
  inboxId,
  { conversations = [] } = {}
) {
  if (!inboxId || !Array.isArray(contacts) || !contacts.length) return [];

  const known = [];
  const needCheck = [];

  contacts.forEach(contact => {
    if (conversationIdForContactInInbox(conversations, contact.id, inboxId)) {
      known.push(contact);
    } else {
      needCheck.push(contact);
    }
  });

  const toCheck = needCheck.slice(0, MAX_CONTACTABLE_CHECKS);
  const checks = await Promise.all(
    toCheck.map(async contact => {
      try {
        const { data } = await ContactAPI.getContactableInboxes(contact.id);
        if (!contactIsReachableOnInbox(data, inboxId)) return null;
        return contact;
      } catch (error) {
        const status = error?.response?.status;
        if (status && status >= 400 && status < 500) return null;
        throw error;
      }
    })
  );

  return [...known, ...checks.filter(Boolean)];
}

async function createConversationForContact({
  contactId,
  inboxId,
  assigneeId,
  conversationId,
}) {
  const { data } = await ContactAPI.getContactableInboxes(contactId);
  const list = contactableInboxList(data);
  const match = list.find(entry => {
    const inbox = entry.inbox || entry;
    return Number(inbox.id) === Number(inboxId);
  });
  if (!match) {
    throw new ForwardError(FORWARD_ERROR_CODES.CONTACT_NOT_REACHABLE);
  }

  const sourceId = match.source_id || match.sourceId;
  const payload = {
    inbox_id: inboxId,
    contact_id: contactId,
    source_id: sourceId,
    assignee_id: assigneeId,
  };
  if (conversationId) {
    payload.conversation_id = conversationId;
  }

  const response = await ConversationApi.create(payload);
  return response.data;
}

// Always go through conversations#create (AgentStartService): reopen+assign,
// or 422 when the thread is open on another agent / outside permission scope.
// Posting to an existing conversationId skips that prepare step and 401s on
// reply? for custom roles with conversation_reply_assigned_only.
export async function resolveDestinationConversationId({
  destination,
  inboxId,
  assigneeId,
}) {
  if (!destination.contactId) {
    throw new ForwardError(FORWARD_ERROR_CODES.DESTINATION_CONTACT_REQUIRED);
  }

  const prepared = await createConversationForContact({
    contactId: destination.contactId,
    inboxId,
    assigneeId,
    conversationId: destination.conversationId,
  });
  return prepared.id;
}

export function messageCreatedAt(message) {
  return Number(message?.created_at ?? message?.createdAt ?? 0);
}

export function sortForwardMessages(messages = []) {
  return [...messages].sort((a, b) => {
    const timeDelta = messageCreatedAt(a) - messageCreatedAt(b);
    if (timeDelta !== 0) return timeDelta;
    return Number(a.id) - Number(b.id);
  });
}

export function dedupeForwardMessages(messages = []) {
  const unique = [];
  messages.forEach(message => {
    if (!message?.id) return;
    if (unique.some(item => Number(item.id) === Number(message.id))) return;
    unique.push(message);
  });
  return unique;
}

async function buildForwardPayload(sourceMessage, contentOverride) {
  const content =
    typeof contentOverride === 'string'
      ? contentOverride
      : sourceMessage.content || '';
  const attachments = getForwardableAttachments(sourceMessage);
  const attachmentIds = attachments
    .map(attachment => attachment.id)
    .filter(id => id != null && id !== '');
  const useServerClone =
    attachments.length > 0 && attachmentIds.length === attachments.length;

  let files = [];
  if (attachments.length > 0 && !useServerClone) {
    files = await fetchAttachmentFiles(attachments);
  }

  if (!content.trim() && files.length === 0 && !useServerClone) {
    throw new ForwardError(FORWARD_ERROR_CODES.NOTHING_TO_FORWARD);
  }

  return {
    content,
    files: useServerClone ? [] : files,
    attachmentIds: useServerClone ? attachmentIds : [],
    contentAttributes: buildForwardContentAttributes(sourceMessage),
  };
}

async function deliverForwardPayload({
  payload,
  conversationId,
  sendMessage,
}) {
  const echoId = getUuid();
  const body = {
    conversationId,
    message: payload.content,
    private: false,
    contentAttributes: payload.contentAttributes,
    echo_id: echoId,
    files: payload.files,
  };
  if (payload.attachmentIds.length) {
    body.attachment_ids = payload.attachmentIds;
  }

  if (typeof sendMessage === 'function') {
    await sendMessage(body);
    return;
  }
  await MessageApi.create(body);
}

export async function forwardMessagesToDestinations({
  sourceMessages,
  destinations,
  inboxId,
  assigneeId,
  sendMessage,
  contentOverride,
  onProgress,
}) {
  const messages = sortForwardMessages(
    dedupeForwardMessages(sourceMessages)
  ).slice(0, MAX_FORWARD_MESSAGES);

  if (!messages.length) {
    throw new ForwardError(FORWARD_ERROR_CODES.NOTHING_TO_FORWARD);
  }

  const singleOverride =
    messages.length === 1 && typeof contentOverride === 'string'
      ? contentOverride
      : undefined;

  const prepared = [];
  await messages.reduce(async (previous, sourceMessage) => {
    await previous;
    prepared.push(await buildForwardPayload(sourceMessage, singleOverride));
  }, Promise.resolve());

  const uniqueDestinations = dedupeDestinations(destinations).slice(
    0,
    MAX_FORWARD_DESTINATIONS
  );

  const results = {
    succeeded: 0,
    failed: 0,
    errors: [],
    failedDestinations: [],
    succeededConversationIds: [],
  };

  await uniqueDestinations.reduce(async (previous, destination, destIndex) => {
    await previous;
    let conversationId;
    try {
      conversationId = await resolveDestinationConversationId({
        destination,
        inboxId,
        assigneeId,
      });
    } catch (error) {
      results.failed += 1;
      results.failedDestinations.push(destination);
      results.errors.push({
        destination,
        ...describeForwardError(error),
      });
      return;
    }

    let destFailed = false;
    await prepared.reduce(async (innerPrevious, payload, msgIndex) => {
      await innerPrevious;
      onProgress?.({
        destinationIndex: destIndex + 1,
        destinationCount: uniqueDestinations.length,
        messageIndex: msgIndex + 1,
        messageCount: prepared.length,
      });
      try {
        await deliverForwardPayload({ payload, conversationId, sendMessage });
      } catch (error) {
        destFailed = true;
        results.errors.push({
          destination,
          ...describeForwardError(error),
        });
      }
    }, Promise.resolve());

    if (destFailed) {
      results.failed += 1;
      results.failedDestinations.push(destination);
      return;
    }

    results.succeeded += 1;
    results.succeededConversationIds.push(conversationId);
  }, Promise.resolve());

  return results;
}

export async function forwardMessageToDestinations({
  sourceMessage,
  destinations,
  inboxId,
  assigneeId,
  sendMessage,
  contentOverride,
}) {
  return forwardMessagesToDestinations({
    sourceMessages: sourceMessage ? [sourceMessage] : [],
    destinations,
    inboxId,
    assigneeId,
    sendMessage,
    contentOverride,
  });
}
