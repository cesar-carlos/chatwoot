<script setup>
import { computed, reactive } from 'vue';
import Message from './Message.vue';
import { MESSAGE_TYPES } from './constants.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMapGetter } from 'dashboard/composables/store.js';
import MessageApi from 'dashboard/api/inbox/message.js';

/**
 * Props definition for the component
 * @typedef {Object} Props
 * @property {Array} readMessages - Array of read messages
 * @property {Array} unReadMessages - Array of unread messages
 * @property {Number} currentUserId - ID of the current user
 * @property {Boolean} isAnEmailChannel - Whether this is an email channel
 * @property {Object} inboxSupportsReplyTo - Inbox reply support configuration
 * @property {Array} messages - Array of all messages [These are not in camelcase]
 */
const props = defineProps({
  currentUserId: {
    type: Number,
    required: true,
  },
  firstUnreadId: {
    type: Number,
    default: null,
  },
  isAnEmailChannel: {
    type: Boolean,
    default: false,
  },
  inboxSupportsReplyTo: {
    type: Object,
    default: () => ({ incoming: false, outgoing: false }),
  },
  messages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['retry']);

const allMessages = computed(() => {
  return useCamelCase(props.messages, {
    deep: true,
    stopPaths: ['content_attributes.translations'],
  });
});

const currentChat = useMapGetter('getSelectedChat');

// Cache for fetched reply messages to avoid duplicate API calls
// Keys are always Number(messageId) to avoid string/number Map misses
const fetchedReplyMessages = reactive(new Map());

const cacheKey = messageId => Number(messageId);

/**
 * Fetches a specific message from the API by trying to get messages around it
 * @param {number} messageId - The ID of the message to fetch
 * @param {number} conversationId - The ID of the conversation
 * @returns {Promise<Object|null>} - The fetched message or null if not found/error
 */
const fetchReplyMessage = async (messageId, conversationId) => {
  const key = cacheKey(messageId);
  // Return cached result if already fetched (or in-flight sentinel)
  if (fetchedReplyMessages.has(key)) {
    return fetchedReplyMessages.get(key);
  }

  // In-flight lock prevents duplicate requests from parallel renders
  fetchedReplyMessages.set(key, undefined);

  try {
    let response = await MessageApi.getPreviousMessages({
      conversationId,
      before: key + 100,
      after: Math.max(0, key - 100),
    });

    let messages = response.data?.payload || [];
    let targetMessage = messages.find(msg => Number(msg.id) === key);

    // FORK: exact id window when ±100 misses (global id gaps across conversations)
    if (!targetMessage) {
      response = await MessageApi.getPreviousMessages({
        conversationId,
        after: key,
        before: key + 1,
      });
      messages = response.data?.payload || [];
      targetMessage = messages.find(msg => Number(msg.id) === key);
    }

    if (targetMessage) {
      const camelCaseMessage = useCamelCase(targetMessage);
      fetchedReplyMessages.set(key, camelCaseMessage);
      return camelCaseMessage;
    }

    fetchedReplyMessages.set(key, null);
    return null;
  } catch (error) {
    fetchedReplyMessages.set(key, null);
    return null;
  }
};

/**
 * Determines if a message should be grouped with the next message
 * @param {Number} index - Index of the current message
 * @param {Array} searchList - Array of messages to check
 * @returns {Boolean} - Whether the message should be grouped with next
 */
const shouldGroupWithNext = (index, searchList) => {
  if (index === searchList.length - 1) return false;

  const current = searchList[index];
  const next = searchList[index + 1];

  if (next.status === 'failed') return false;

  const nextSenderId = next.senderId ?? next.sender?.id;
  const currentSenderId = current.senderId ?? current.sender?.id;
  const hasSameSender = nextSenderId === currentSenderId;

  const nextMessageType = next.messageType;
  const currentMessageType = current.messageType;

  const areBothTemplates =
    nextMessageType === MESSAGE_TYPES.TEMPLATE &&
    currentMessageType === MESSAGE_TYPES.TEMPLATE;

  if (!hasSameSender || areBothTemplates) return false;

  if (currentMessageType !== nextMessageType) return false;

  // Check if messages are in the same minute by rounding down to nearest minute
  return Math.floor(next.createdAt / 60) === Math.floor(current.createdAt / 60);
};

/**
 * Determines if a message is unread based on the firstUnreadId
 * @param {Object} message - The message to check
 * @returns {boolean} - Whether the message is unread
 */
const isMessageUnread = message => {
  if (!props.firstUnreadId) return false;
  return message.id >= props.firstUnreadId;
};

/**
 * Gets the message that was replied to
 * @param {Object} parentMessage - The message containing the reply reference
 * @returns {Object|null} - The message being replied to, or null if not found
 */
const getInReplyToMessage = parentMessage => {
  if (!parentMessage) return null;

  const inReplyToMessageId =
    parentMessage.contentAttributes?.inReplyTo ??
    parentMessage.contentAttributes?.in_reply_to ??
    parentMessage.content_attributes?.in_reply_to;

  if (!inReplyToMessageId) return null;

  const key = cacheKey(inReplyToMessageId);
  const matchesId = msg => Number(msg.id) === key;
  // FORK: distinguish loading vs missing so the quote preview does not flash "not found"
  const stub = (state = 'missing') => ({
    id: key,
    replyPreviewState: state,
  });

  // Try to find in current messages first
  let replyMessage = props.messages?.find(matchesId);

  // Then try store messages
  if (!replyMessage && currentChat.value?.messages) {
    replyMessage = currentChat.value.messages.find(matchesId);
  }

  // Then check fetch cache (undefined = in-flight, null = not found)
  if (!replyMessage && fetchedReplyMessages.has(key)) {
    const cached = fetchedReplyMessages.get(key);
    if (cached) return cached;
    return stub(cached === null ? 'missing' : 'loading');
  }

  // If still not found and we have conversation context, fetch it
  if (!replyMessage && currentChat.value?.id) {
    fetchReplyMessage(key, currentChat.value.id);
    return stub('loading');
  }

  if (!replyMessage) {
    return stub('missing');
  }

  return useCamelCase(replyMessage);
};
</script>

<template>
  <ul class="px-4 bg-n-surface-1">
    <slot name="beforeAll" />
    <template v-for="(message, index) in allMessages" :key="message.id">
      <slot
        v-if="firstUnreadId && message.id === firstUnreadId"
        name="unreadBadge"
      />
      <Message
        v-bind="message"
        :class="isMessageUnread(message) ? 'message--unread' : 'message--read'"
        :is-email-inbox="isAnEmailChannel"
        :in-reply-to="getInReplyToMessage(message)"
        :group-with-next="shouldGroupWithNext(index, allMessages)"
        :inbox-supports-reply-to="inboxSupportsReplyTo"
        :current-user-id="currentUserId"
        data-clarity-mask="True"
        @retry="emit('retry', message)"
      />
    </template>
    <slot name="after" />
  </ul>
</template>
