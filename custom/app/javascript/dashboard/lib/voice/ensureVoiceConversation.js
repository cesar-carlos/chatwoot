import ContactAPI from 'dashboard/api/contacts';
import ConversationApi from 'dashboard/api/conversations';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export async function findVoiceConversationId(contactId, inboxId) {
  const { data } = await ContactAPI.getConversations(contactId, { inboxId });
  const conversations = data?.payload || [];
  const match = [...conversations].sort(
    (a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0)
  )[0];
  return match?.id || null;
}

const wavoipSourceId = phone => phone?.replace(/^\+/, '') || '';

export async function ensureVoiceConversation({
  contactId,
  inboxId,
  phone,
  channelType,
}) {
  const existing = await findVoiceConversationId(contactId, inboxId);
  if (existing) return existing;

  const payload = {
    inbox_id: inboxId,
    contact_id: contactId,
  };

  if (channelType === INBOX_TYPES.WAVOIP) {
    payload.source_id = wavoipSourceId(phone);
  }

  const { data } = await ConversationApi.create(payload);
  return data?.id || null;
}
