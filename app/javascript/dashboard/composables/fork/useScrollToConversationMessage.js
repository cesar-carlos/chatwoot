import { ref, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import types from 'dashboard/store/mutation-types';
import { useAlert } from 'dashboard/composables';

const HIGHLIGHT_CLASS = 'bg-n-alpha-1';
const HIGHLIGHT_DURATION_MS = 1000;
const INJECTED_MESSAGE_LIMIT = 50;

const injectedIdsByConversation = new Map();

const prefersReducedMotion = () =>
  typeof window !== 'undefined' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const mergeMessageIntoStore = (store, conversationId, selectedMessage) => {
  const chat = store.getters.getSelectedChat;
  if (!chat || chat.id !== conversationId) return;

  const latestMessages = store.getters.getSelectedChat?.messages || [];
  const wasPresent = latestMessages.some(
    message => message.id === selectedMessage.id
  );

  const messageMap = new Map(
    latestMessages.map(message => [message.id, message])
  );
  messageMap.set(selectedMessage.id, selectedMessage);

  let mergedMessages = Array.from(messageMap.values()).sort(
    (left, right) => new Date(left.created_at) - new Date(right.created_at)
  );

  if (!wasPresent) {
    const injectedIds = [
      ...(injectedIdsByConversation.get(conversationId) || []),
      selectedMessage.id,
    ];

    if (injectedIds.length > INJECTED_MESSAGE_LIMIT) {
      const overflow = injectedIds.slice(
        0,
        injectedIds.length - INJECTED_MESSAGE_LIMIT
      );
      const removeSet = new Set(
        overflow.filter(id => id !== selectedMessage.id)
      );
      mergedMessages = mergedMessages.filter(
        message => !removeSet.has(message.id)
      );
    }

    injectedIdsByConversation.set(
      conversationId,
      injectedIds.slice(-INJECTED_MESSAGE_LIMIT)
    );
  }

  store.commit(types.SET_MISSING_MESSAGES, {
    id: conversationId,
    data: mergedMessages,
  });
};

const applyTemporaryHighlight = messageId => {
  const messageElement = document.getElementById(`message${messageId}`);
  if (!messageElement) return;

  if (prefersReducedMotion()) {
    messageElement.classList.add(HIGHLIGHT_CLASS);
    messageElement.classList.remove(HIGHLIGHT_CLASS);
    return;
  }

  messageElement.classList.add(HIGHLIGHT_CLASS);
  window.setTimeout(() => {
    messageElement.classList.remove(HIGHLIGHT_CLASS);
  }, HIGHLIGHT_DURATION_MS);
};

export const useScrollToConversationMessage = ({ conversationId, onClose }) => {
  const store = useStore();
  const { t } = useI18n();
  const isLocating = ref(false);

  const scrollToMessage = async selectedMessage => {
    if (!selectedMessage?.id || isLocating.value) return false;

    isLocating.value = true;
    const { id: messageId } = selectedMessage;

    try {
      let messageElement = document.getElementById(`message${messageId}`);

      if (!messageElement) {
        mergeMessageIntoStore(store, conversationId, selectedMessage);
        await nextTick();
        messageElement = document.getElementById(`message${messageId}`);
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
