// FORK: WhatsApp Evolution Go/Node group participant sender label

import { describe, it, expect } from 'vitest';
import { ref } from 'vue';
import { useGroupMessageSender } from '../useGroupMessageSender';

describe('useGroupMessageSender', () => {
  it('reads evolution_go_participant_push_name from content attributes', () => {
    const attrs = ref({
      evolution_go_participant_push_name: 'Group Member',
    });
    const { senderName, isGroupMessage } = useGroupMessageSender(attrs);

    expect(senderName.value).toBe('Group Member');
    expect(isGroupMessage.value).toBe(true);
  });

  it('falls back to participant jid digits when push name is missing', () => {
    const attrs = ref({
      evolution_go_participant_jid: '5511777777777@s.whatsapp.net',
    });
    const { senderName, isGroupMessage } = useGroupMessageSender(attrs);

    expect(senderName.value).toBe('5511777777777');
    expect(isGroupMessage.value).toBe(true);
  });

  it('returns empty when participant name and jid are missing', () => {
    const attrs = ref({});
    const { senderName, isGroupMessage } = useGroupMessageSender(attrs);

    expect(senderName.value).toBe('');
    expect(isGroupMessage.value).toBe(false);
  });

  it('accepts a message object with content_attributes', () => {
    const message = ref({
      content_attributes: {
        evolution_go_participant_push_name: 'Alice',
      },
    });
    const { senderName } = useGroupMessageSender(message);

    expect(senderName.value).toBe('Alice');
  });
});
