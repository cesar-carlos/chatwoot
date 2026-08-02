// FORK: WhatsApp Evolution Go/Node group participant sender label

import { computed, unref } from 'vue';

/**
 * @param {string} jid
 * @returns {string}
 */
function formatParticipantJid(jid) {
  const value = String(jid || '').trim();
  if (!value) return '';

  const local = value.split('@')[0] || '';
  return local.replace(/\D/g, '') || local;
}

/**
 * @param {import('vue').Ref|Object} messageOrAttrs - message object or content_attributes ref
 * @returns {{ senderName: import('vue').ComputedRef<string>, isGroupMessage: import('vue').ComputedRef<boolean> }}
 */
export function useGroupMessageSender(messageOrAttrs) {
  const attrs = computed(() => {
    const value = unref(messageOrAttrs);
    if (!value) return {};
    if (value.content_attributes || value.contentAttributes) {
      return value.content_attributes || value.contentAttributes || {};
    }
    return value;
  });

  const participantJid = computed(() => {
    return (
      attrs.value.evolution_go_participant_jid ||
      attrs.value.evolution_participant_jid ||
      ''
    );
  });

  const senderName = computed(() => {
    const name =
      attrs.value.evolution_go_participant_push_name ||
      attrs.value.evolution_participant_push_name ||
      '';
    const trimmed = String(name).trim();
    if (trimmed) return trimmed;

    return formatParticipantJid(participantJid.value);
  });

  const isGroupMessage = computed(
    () =>
      senderName.value.length > 0 ||
      String(participantJid.value).trim().length > 0
  );

  return { senderName, isGroupMessage };
}
