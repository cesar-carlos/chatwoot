import { MESSAGE_TYPE } from 'shared/constants/messages';

/**
 * Normalizes message timestamps for reliable comparisons.
 * @param {Object} message
 * @returns {number}
 */
export const messageCreatedAtTimestamp = message => {
  if (!message) return 0;

  const raw = message.created_at ?? message.createdAt;
  if (raw == null || raw === '') return 0;

  const numeric = Number(raw);
  return Number.isFinite(numeric) ? numeric : 0;
};

export const isNonActivityMessage = message =>
  Boolean(message) && message.message_type !== MESSAGE_TYPE.ACTIVITY;

/**
 * Determines the last non-activity message between store and API messages.
 * @param {Object} messageInStore - The last non-activity message from the store.
 * @param {Object} messageFromAPI - The last non-activity message from the API.
 * @returns {Object} The latest non-activity message.
 */
export const getLastNonActivityMessage = (messageInStore, messageFromAPI) => {
  if (messageInStore && messageFromAPI) {
    return messageCreatedAtTimestamp(messageInStore) >=
      messageCreatedAtTimestamp(messageFromAPI)
      ? messageInStore
      : messageFromAPI;
  }

  return messageInStore || messageFromAPI;
};

export const getLastNonActivityMessageFromList = (messages = []) => {
  const nonActivityMessages = messages.filter(isNonActivityMessage);
  return nonActivityMessages[nonActivityMessages.length - 1];
};

export const mergeConversationListMessages = (
  existingMessages = [],
  incomingMessages = []
) => {
  const messageMap = new Map();

  [...incomingMessages, ...existingMessages].forEach(message => {
    if (!message?.id) return;
    messageMap.set(message.id, message);
  });

  return Array.from(messageMap.values()).sort(
    (left, right) =>
      messageCreatedAtTimestamp(left) - messageCreatedAtTimestamp(right)
  );
};

export const mergeConversationOnListRefresh = (existing, incoming) => {
  if (!existing) return incoming;

  const mergedMessages = mergeConversationListMessages(
    existing.messages,
    incoming.messages
  );

  const lastNonActivityMessage = getLastNonActivityMessage(
    getLastNonActivityMessage(
      getLastNonActivityMessageFromList(existing.messages),
      existing.last_non_activity_message || existing.lastNonActivityMessage
    ),
    getLastNonActivityMessage(
      getLastNonActivityMessageFromList(incoming.messages),
      incoming.last_non_activity_message || incoming.lastNonActivityMessage
    )
  );

  return {
    ...incoming,
    messages: mergedMessages,
    last_non_activity_message: lastNonActivityMessage,
  };
};

/**
 * Filters out duplicate source messages from an array of messages.
 * @param {Array} messages - The array of messages to filter.
 * @returns {Array} An array of messages without duplicates.
 */
export const filterDuplicateSourceMessages = (messages = []) => {
  const messagesWithoutDuplicates = [];
  // We cannot use Map or any short hand method as it returns the last message with the duplicate ID
  // We should return the message with smaller id when there is a duplicate
  messages.forEach(m1 => {
    if (m1.source_id) {
      const index = messagesWithoutDuplicates.findIndex(
        m2 => m1.source_id === m2.source_id
      );

      if (index < 0) {
        messagesWithoutDuplicates.push(m1);
      }
    } else {
      messagesWithoutDuplicates.push(m1);
    }
  });
  return messagesWithoutDuplicates;
};

/**
 * Retrieves the last message from a conversation, prioritizing non-activity messages.
 * @param {Object} m - The conversation object containing messages.
 * @returns {Object} The last message of the conversation.
 */
export const getLastMessage = m => {
  const messages = m.messages || [];
  const lastMessageIncludingActivity = messages[messages.length - 1];
  const lastNonActivityMessageInStore =
    getLastNonActivityMessageFromList(messages);
  const lastNonActivityMessageFromAPI =
    m.last_non_activity_message || m.lastNonActivityMessage;

  if (!lastNonActivityMessageInStore && !lastNonActivityMessageFromAPI) {
    return lastMessageIncludingActivity;
  }

  return getLastNonActivityMessage(
    lastNonActivityMessageInStore,
    lastNonActivityMessageFromAPI
  );
};

/**
 * Filters messages that have been read by the agent.
 * @param {Array} messages - The array of messages to filter.
 * @param {number} agentLastSeenAt - The timestamp of when the agent last saw the messages.
 * @returns {Array} An array of read messages.
 */
export const getReadMessages = (messages, agentLastSeenAt) => {
  return messages.filter(
    message => message.created_at * 1000 <= agentLastSeenAt * 1000
  );
};

/**
 * Filters messages that have not been read by the agent.
 * @param {Array} messages - The array of messages to filter.
 * @param {number} agentLastSeenAt - The timestamp of when the agent last saw the messages.
 * @returns {Array} An array of unread messages.
 */
export const getUnreadMessages = (messages, agentLastSeenAt) => {
  return messages.filter(
    message => message.created_at * 1000 > agentLastSeenAt * 1000
  );
};
