import {
  filterDuplicateSourceMessages,
  getLastMessage,
  getLastNonActivityMessage,
  getReadMessages,
  getUnreadMessages,
  mergeConversationListMessages,
  mergeConversationOnListRefresh,
  messageCreatedAtTimestamp,
} from '../conversationHelper';
import {
  conversationData,
  lastMessageData,
  readMessagesData,
  unReadMessagesData,
} from './fixtures/conversationFixtures';

describe('conversationHelper', () => {
  describe('#filterDuplicateSourceMessages', () => {
    it('returns messages without duplicate source_id and all messages without source_id', () => {
      const input = [
        { source_id: null, id: 1 },
        { source_id: '', id: 2 },
        { id: 3 },
        { source_id: 'wa_1', id: 4 },
        { source_id: 'wa_1', id: 5 },
        { source_id: 'wa_1', id: 6 },
        { source_id: 'wa_2', id: 7 },
        { source_id: 'wa_2', id: 8 },
        { source_id: 'wa_3', id: 9 },
      ];
      const expected = [
        { source_id: null, id: 1 },
        { source_id: '', id: 2 },
        { id: 3 },
        { source_id: 'wa_1', id: 4 },
        { source_id: 'wa_2', id: 7 },
        { source_id: 'wa_3', id: 9 },
      ];
      expect(filterDuplicateSourceMessages(input)).toEqual(expected);
    });
  });

  describe('#readMessages', () => {
    it('should return read messages if conversation is passed', () => {
      expect(
        getReadMessages(
          conversationData.messages,
          conversationData.agent_last_seen_at
        )
      ).toEqual(readMessagesData);
    });
  });

  describe('#unReadMessages', () => {
    it('should return unread messages if conversation is passed', () => {
      expect(
        getUnreadMessages(
          conversationData.messages,
          conversationData.agent_last_seen_at
        )
      ).toEqual(unReadMessagesData);
    });
  });

  describe('#lastMessage', () => {
    it("should return last activity message if both api and store doesn't have other messages", () => {
      const testConversation = {
        messages: [conversationData.messages[0]],
        last_non_activity_message: null,
      };
      expect(getLastMessage(testConversation)).toEqual(
        testConversation.messages[0]
      );
    });

    it('should return message from store if store has latest message', () => {
      const testConversation = {
        messages: [],
        last_non_activity_message: lastMessageData,
      };
      expect(getLastMessage(testConversation)).toEqual(lastMessageData);
    });

    it('should return last non activity message from store if api value is empty', () => {
      const testConversation = {
        messages: [conversationData.messages[0], conversationData.messages[1]],
        last_non_activity_message: null,
      };
      expect(getLastMessage(testConversation)).toEqual(
        testConversation.messages[1]
      );
    });

    it("should return last non activity message from store if store doesn't have any messages", () => {
      const testConversation = {
        messages: [conversationData.messages[1], conversationData.messages[2]],
        last_non_activity_message: conversationData.messages[0],
      };
      expect(getLastMessage(testConversation)).toEqual(
        testConversation.messages[1]
      );
    });

    it('should return preview message from camelCase API field', () => {
      const testConversation = {
        messages: [],
        lastNonActivityMessage: lastMessageData,
      };
      expect(getLastMessage(testConversation)).toEqual(lastMessageData);
    });
  });

  describe('#getLastNonActivityMessage', () => {
    it('compares timestamps when created_at types differ', () => {
      const older = { ...lastMessageData, created_at: '1621145476' };
      const newer = { ...lastMessageData, id: 999, created_at: 1621145477 };

      expect(getLastNonActivityMessage(older, newer)).toEqual(newer);
      expect(getLastNonActivityMessage(newer, older)).toEqual(newer);
    });
  });

  describe('#mergeConversationOnListRefresh', () => {
    it('keeps the newest websocket preview when list data is refreshed', () => {
      const existing = {
        id: 1,
        messages: [
          { id: 10, message_type: 0, content: 'live', created_at: 20 },
        ],
        last_non_activity_message: {
          id: 10,
          message_type: 0,
          content: 'live',
          created_at: 20,
        },
      };
      const incoming = {
        id: 1,
        messages: [
          { id: 9, message_type: 0, content: 'stale', created_at: 10 },
        ],
        last_non_activity_message: {
          id: 9,
          message_type: 0,
          content: 'stale',
          created_at: 10,
        },
      };

      const merged = mergeConversationOnListRefresh(existing, incoming);

      expect(merged.last_non_activity_message.content).toBe('live');
      expect(merged.messages.map(message => message.id)).toEqual([9, 10]);
    });
  });

  describe('#messageCreatedAtTimestamp', () => {
    it('normalizes numeric and string timestamps', () => {
      expect(messageCreatedAtTimestamp({ created_at: 1621145476 })).toBe(
        1621145476
      );
      expect(messageCreatedAtTimestamp({ created_at: '1621145476' })).toBe(
        1621145476
      );
      expect(messageCreatedAtTimestamp({ createdAt: 1621145477 })).toBe(
        1621145477
      );
    });
  });

  describe('#mergeConversationListMessages', () => {
    it('merges message arrays without losing websocket updates', () => {
      const merged = mergeConversationListMessages(
        [{ id: 2, created_at: 2 }],
        [{ id: 1, created_at: 1 }]
      );

      expect(merged.map(message => message.id)).toEqual([1, 2]);
    });
  });
});
