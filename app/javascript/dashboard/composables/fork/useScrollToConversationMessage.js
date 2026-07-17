import { ref, nextTick, unref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import types from 'dashboard/store/mutation-types';
import { useAlert } from 'dashboard/composables';
import MessageApi from 'dashboard/api/inbox/message';
import {
  collectVisibleMessageIds,
  newMessageIds,
} from 'dashboard/composables/fork/conversationSearchInjectedMessages';

const HIGHLIGHT_CLASS = 'message-locate-pulse';
const HIGHLIGHT_DURATION_MS = 1800;
const MESSAGE_WINDOW = 100;

const prefersReducedMotion = () =>
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const messageElementId = messageId => `message${messageId}`;

const findMessageElement = messageId =>
  document.getElementById(messageElementId(messageId));

const insertMessagesAround = (
  store,
  conversationId,
  messages,
  targetMessageId
) => {
  const chat = store.getters.getSelectedChat;
  if (!chat || chat.id !== conversationId) return;

  const injectedIds = newMessageIds(chat.messages, messages);

  store.commit(types.INSERT_MESSAGES_AROUND, {
    id: conversationId,
    data: messages,
  });

  if (!injectedIds.length) return;

  store.commit(types.REGISTER_SEARCH_INJECTED, {
    id: conversationId,
    messageIds: injectedIds,
  });
  store.commit(types.PRUNE_SEARCH_INJECTED, {
    id: conversationId,
    // Normalize ids so Set lookup matches message.id from the store
    protectedIds: [Number(targetMessageId), ...collectVisibleMessageIds()].map(
      Number
    ),
  });
};

const payloadIncludesMessage = (messages, messageId) =>
  (messages || []).some(message => Number(message.id) === Number(messageId));

const loadMessagesAround = async (conversationId, messageId) => {
  const response = await MessageApi.getPreviousMessages({
    conversationId,
    before: messageId + MESSAGE_WINDOW,
    after: Math.max(0, messageId - MESSAGE_WINDOW),
  });

  let messages = response.data?.payload || [];
  if (payloadIncludesMessage(messages, messageId)) {
    return messages;
  }

  // Exact id window: MessageFinder#messages_between uses id >= after AND id < before
  const tight = await MessageApi.getPreviousMessages({
    conversationId,
    after: messageId,
    before: messageId + 1,
  });
  messages = tight.data?.payload || [];
  return messages;
};

const applyTemporaryHighlight = messageId => {
  const messageElement = findMessageElement(messageId);
  if (!messageElement) return;

  const previousTimer = messageElement.dataset.locatePulseTimer;
  if (previousTimer) {
    window.clearTimeout(Number(previousTimer));
  }

  messageElement.classList.remove(
    HIGHLIGHT_CLASS,
    'ring-2',
    'ring-n-brand',
    'bg-n-alpha-1'
  );
  // Force reflow so re-clicking the same quote restarts the animation
  // eslint-disable-next-line no-unused-expressions
  messageElement.offsetWidth;

  const clearHighlight = () => {
    messageElement.classList.remove(
      HIGHLIGHT_CLASS,
      'ring-2',
      'ring-n-brand',
      'bg-n-alpha-1'
    );
    delete messageElement.dataset.locatePulseTimer;
  };

  if (prefersReducedMotion()) {
    messageElement.classList.add('ring-2', 'ring-n-brand', 'bg-n-alpha-1');
  } else {
    messageElement.classList.add(HIGHLIGHT_CLASS);
  }

  const timerId = window.setTimeout(clearHighlight, HIGHLIGHT_DURATION_MS);
  messageElement.dataset.locatePulseTimer = String(timerId);
};

const canRenderBubble = message => {
  if (!message?.id) return false;
  return Boolean(
    message.content ||
      message.attachments?.length ||
      message.content_attributes ||
      message.contentAttributes
  );
};

export const useScrollToConversationMessage = ({
  conversationId: conversationIdSource,
  onClose,
}) => {
  const store = useStore();
  const { t } = useI18n();
  const isLocating = ref(false);

  const scrollToMessage = async selectedMessage => {
    if (!selectedMessage?.id || isLocating.value) return false;

    const conversationId = unref(conversationIdSource);
    if (!conversationId) return false;

    isLocating.value = true;
    const { id: messageId } = selectedMessage;

    try {
      let messageElement = findMessageElement(messageId);

      // Skip stub inserts ({ id } only) — Message.vue won't render them
      if (!messageElement && canRenderBubble(selectedMessage)) {
        insertMessagesAround(
          store,
          conversationId,
          [selectedMessage],
          messageId
        );
        await nextTick();
        messageElement = findMessageElement(messageId);
      }

      if (!messageElement) {
        try {
          const aroundMessages = await loadMessagesAround(
            conversationId,
            messageId
          );
          if (aroundMessages.length) {
            insertMessagesAround(
              store,
              conversationId,
              aroundMessages,
              messageId
            );
            await nextTick();
            // Second tick: MessageList may need an extra frame after store merge
            await nextTick();
            messageElement = findMessageElement(messageId);
          }
        } catch {
          // Fall through to not-found alert.
        }
      }

      if (!messageElement) {
        useAlert(t('CONVERSATION.MESSAGE_SEARCH.MESSAGE_NOT_FOUND'));
        return false;
      }

      onClose?.();
      emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
      // Wait for smooth scrollIntoView to settle before pulsing the target
      await nextTick();
      window.setTimeout(() => applyTemporaryHighlight(messageId), 350);
      return true;
    } finally {
      isLocating.value = false;
    }
  };

  return {
    scrollToMessage,
    isLocating,
  };
};
