import { describe, it, expect } from 'vitest';
import {
  inboxSupportsMessageEdit,
  messageCanBeEdited,
  stripEditedPrefix,
  EDITED_PREFIX,
} from 'customDashboard/composables/useMessageEdit';

describe('useMessageEdit', () => {
  describe('inboxSupportsMessageEdit', () => {
    it('requires evolution_go with sync_edit_to_whatsapp', () => {
      expect(
        inboxSupportsMessageEdit({
          channel_type: 'Channel::Whatsapp',
          provider: 'evolution_go',
          provider_config: { sync_edit_to_whatsapp: true },
        })
      ).toBe(true);

      // Agents receive the flag at inbox top-level (not full provider_config).
      expect(
        inboxSupportsMessageEdit({
          channel_type: 'Channel::Whatsapp',
          provider: 'evolution_go',
          sync_edit_to_whatsapp: true,
        })
      ).toBe(true);

      expect(
        inboxSupportsMessageEdit({
          channel_type: 'Channel::Whatsapp',
          provider: 'evolution_go',
          provider_config: { sync_edit_to_whatsapp: false },
        })
      ).toBe(false);

      expect(
        inboxSupportsMessageEdit({
          channel_type: 'Channel::Whatsapp',
          provider: 'evolution',
          provider_config: { sync_edit_to_whatsapp: true },
        })
      ).toBe(false);
    });
  });

  describe('messageCanBeEdited', () => {
    it('allows outgoing public messages with source_id and text', () => {
      expect(
        messageCanBeEdited({
          message_type: 1,
          private: false,
          source_id: 'ABC',
          content: 'hello',
          content_attributes: {},
        })
      ).toBe(true);
    });

    it('allows media captions (content + attachments)', () => {
      expect(
        messageCanBeEdited({
          message_type: 1,
          source_id: 'ABC',
          content: 'caption text',
          attachments: [{ file_type: 'image' }],
          content_attributes: {},
        })
      ).toBe(true);
    });

    it('rejects attachment-only messages without text', () => {
      expect(
        messageCanBeEdited({
          message_type: 1,
          source_id: 'ABC',
          content: '',
          attachments: [{ file_type: 'image' }],
          content_attributes: {},
        })
      ).toBe(false);
    });

    it('rejects deleted, private, incoming, or missing source_id', () => {
      expect(
        messageCanBeEdited({
          message_type: 1,
          source_id: 'ABC',
          content: 'hello',
          content_attributes: { deleted: true },
        })
      ).toBe(false);

      expect(
        messageCanBeEdited({
          message_type: 0,
          source_id: 'ABC',
          content: 'hello',
        })
      ).toBe(false);

      expect(
        messageCanBeEdited({
          message_type: 1,
          private: true,
          source_id: 'ABC',
          content: 'hello',
        })
      ).toBe(false);

      expect(
        messageCanBeEdited({
          message_type: 1,
          content: 'hello',
        })
      ).toBe(false);
    });
  });

  describe('stripEditedPrefix', () => {
    it('removes the edited prefix when present', () => {
      expect(stripEditedPrefix(`${EDITED_PREFIX}body`)).toBe('body');
      expect(stripEditedPrefix('plain')).toBe('plain');
    });
  });
});
