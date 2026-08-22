import { getVoiceCallProvider } from 'dashboard/helper/inbox';
import { handleVoiceCallCreated } from 'dashboard/helper/voice';

const conversationFingerprints = new Map();

const conversationFingerprint = conversation => {
  const messages = conversation?.messages;
  const length = messages?.length || 0;
  const lastId = length ? messages[length - 1]?.id : '';
  return `${conversation?.id}:${length}:${lastId}`;
};

export function resetSeedVoiceCallsFingerprints() {
  conversationFingerprints.clear();
}

export function seedVoiceCallsFromHydratedMessages({
  conversations = [],
  inboxes = [],
  currentUserId,
  currentUserAvailability,
} = {}) {
  if (!inboxes.some(inbox => getVoiceCallProvider(inbox) != null)) return;

  conversations.forEach(conversation => {
    const messages = conversation?.messages;
    if (!messages?.length) return;

    const fingerprint = conversationFingerprint(conversation);
    if (conversationFingerprints.get(conversation.id) === fingerprint) return;
    conversationFingerprints.set(conversation.id, fingerprint);

    messages.forEach(message => {
      handleVoiceCallCreated(message, currentUserId, currentUserAvailability);
    });
  });
}
