import { ref, nextTick, unref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import types from 'dashboard/store/mutation-types';
import { useAlert } from 'dashboard/composables';
import MessageApi from 'dashboard/api/inbox/message';

const HIGHLIGHT_CLASS = 'bg-n-alpha-1';
const HIGHLIGHT_DURATION_MS = 1000;
const MESSAGE_WINDOW = 100;

const prefersReducedMotion = () =>
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const insertMessagesAround = (store, conversationId, messages) => {
  const chat = store.getters.getSelectedChat;
  if (!chat || chat.id !== conversationId) return;

  store.commit(types.INSERT_MESSAGES_AROUND, {
    id: conversationId,
    data: messages,
  });
};

const loadMessagesAround = async (conversationId, messageId) => {
  const response = await MessageApi.getPreviousMessages({
    conversationId,
    before: messageId + MESSAGE_WINDOW,
    after: messageId - MESSAGE_WINDOW,
  });

  return response.data?.payload || [];
};

const applyTemporaryHighlight = messageId => {
  const messageElement = document.getElementById(`message${messageId}`);
  if (!messageElement) return;

  if (prefersReducedMotion()) {
    messageElement.classList.add('ring-2', 'ring-n-brand');
    window.setTimeout(() => {
      messageElement.classList.remove('ring-2', 'ring-n-brand');
    }, HIGHLIGHT_DURATION_MS);
    return;
  }

  messageElement.classList.add(HIGHLIGHT_CLASS);
  window.setTimeout(() => {
    messageElement.classList.remove(HIGHLIGHT_CLASS);
  }, HIGHLIGHT_DURATION_MS);
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
      let messageElement = document.getElementById(`message${messageId}`);

      if (!messageElement) {
        insertMessagesAround(store, conversationId, [selectedMessage]);
        await nextTick();
        messageElement = document.getElementById(`message${messageId}`);
      }

      if (!messageElement) {
        try {
          const aroundMessages = await loadMessagesAround(
            conversationId,
            messageId
          );
          if (aroundMessages.length) {
            insertMessagesAround(store, conversationId, aroundMessages);
            await nextTick();
            messageElement = document.getElementById(`message${messageId}`);
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
      await nextTick();
      applyTemporaryHighlight(messageId);
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
