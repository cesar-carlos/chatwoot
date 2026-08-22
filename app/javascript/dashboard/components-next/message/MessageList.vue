<script setup>
import { computed, provide, toRef, watch } from 'vue';
import Message from './Message.vue';
import CampaignMessage from './CampaignMessage.vue';
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
  campaignHistory: {
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

const timeline = computed(() => {
  const messages = allMessages.value.map(message => ({
    key: `message-${message.id}`,
    createdAt: message.createdAt,
    message,
  }));
  if (!props.campaignHistory.length) return messages;

  return [
    ...messages,
    ...props.campaignHistory.map(recipient => ({
      key: `campaign-${recipient.id}`,
      createdAt: recipient.sent_at,
      recipient,
    })),
  ].sort((a, b) => a.createdAt - b.createdAt);
});

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
 * @param {Object} current - Current message
 * @param {Object} next - Next message, absent at a campaign entry or the end
 * @returns {Boolean} - Whether the message should be grouped with next
 */
const shouldGroupWithNext = (current, next) => {
  if (!next || next.status === 'failed') return false;

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
    <template v-for="(entry, index) in timeline" :key="entry.key">
      <slot
        v-if="firstUnreadId && entry.message?.id === firstUnreadId"
        name="unreadBadge"
      />
      <CampaignMessage v-if="entry.recipient" :recipient="entry.recipient" />
      <Message
        v-else
        v-bind="entry.message"
        :class="
          isMessageUnread(entry.message) ? 'message--unread' : 'message--read'
        "
        :is-email-inbox="isAnEmailChannel"
        :in-reply-to="getInReplyToMessage(entry.message)"
        :group-with-next="
          shouldGroupWithNext(entry.message, timeline[index + 1]?.message)
        "
        :inbox-supports-reply-to="inboxSupportsReplyTo"
        :current-user-id="currentUserId"
        data-clarity-mask="True"
        @retry="emit('retry', entry.message)"
      />
    </template>
    <slot name="after" />
  </ul>
</template>
