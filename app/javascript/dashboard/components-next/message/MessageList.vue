<script setup>
import { computed, provide, toRef, watch } from 'vue';
import Message from './Message.vue';
import { MESSAGE_TYPES } from './constants.js';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useMapGetter } from 'dashboard/composables/store.js';
// FORK: shared quote locate + in-reply-to resolver
import {
  LocateConversationMessageKey,
  useScrollToConversationMessage,
} from 'dashboard/composables/fork/useScrollToConversationMessage';
import { useInReplyToMessage } from 'dashboard/composables/fork/useInReplyToMessage';
// FORK: multi-select forward timeline order for Shift+click
import { useMessageForwardSelection } from 'customDashboard/composables/useMessageForwardSelection';

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
    stopPaths: [
      'content_attributes.translations',
      'content_attributes.whatsapp_flow_response.response_json',
    ],
  });
});

const currentChat = useMapGetter('getSelectedChat');

const conversationId = computed(() => currentChat.value?.id);

// FORK: one locate instance for the whole conversation thread
const locateConversationMessage = useScrollToConversationMessage({
  conversationId,
});
provide(LocateConversationMessageKey, locateConversationMessage);

const { getInReplyToMessage } = useInReplyToMessage({
  messages: toRef(props, 'messages'),
  currentChat,
});

const forwardSelection = useMessageForwardSelection();
watch(
  allMessages,
  messages => {
    forwardSelection?.setTimeline?.(messages);
  },
  { immediate: true }
);

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
