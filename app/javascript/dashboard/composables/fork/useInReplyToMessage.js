import { reactive, unref } from 'vue';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import MessageApi from 'dashboard/api/inbox/message';

const cacheKey = messageId => Number(messageId);

/**
 * Resolves the parent message for a quoted reply, fetching outside the
 * lazy-loaded window when needed. Keys are always Number(id).
 *
 * @param {Object} options
 * @param {import('vue').Ref|import('vue').ComputedRef|Object} options.messages - Current list (snake_case)
 * @param {import('vue').Ref|import('vue').ComputedRef|Object} options.currentChat - Selected chat from store
 */
export const useInReplyToMessage = ({ messages, currentChat }) => {
  const fetchedReplyMessages = reactive(new Map());

  const fetchReplyMessage = async (messageId, conversationId) => {
    const key = cacheKey(messageId);
    if (fetchedReplyMessages.has(key)) {
      return fetchedReplyMessages.get(key);
    }

    fetchedReplyMessages.set(key, undefined);

    try {
      // Tight-first exact id window
      let response = await MessageApi.getPreviousMessages({
        conversationId,
        after: key,
        before: key + 1,
      });

      let payload = response.data?.payload || [];
      let targetMessage = payload.find(msg => Number(msg.id) === key);

      if (!targetMessage) {
        response = await MessageApi.getPreviousMessages({
          conversationId,
          before: key + 100,
          after: Math.max(0, key - 100),
        });
        payload = response.data?.payload || [];
        targetMessage = payload.find(msg => Number(msg.id) === key);
      }

      if (targetMessage) {
        const camelCaseMessage = useCamelCase(targetMessage);
        fetchedReplyMessages.set(key, camelCaseMessage);
        return camelCaseMessage;
      }

      fetchedReplyMessages.set(key, null);
      return null;
    } catch {
      fetchedReplyMessages.set(key, null);
      return null;
    }
  };

  const getInReplyToMessage = parentMessage => {
    if (!parentMessage) return null;

    const inReplyToMessageId =
      parentMessage.contentAttributes?.inReplyTo ??
      parentMessage.contentAttributes?.in_reply_to ??
      parentMessage.content_attributes?.in_reply_to;

    if (!inReplyToMessageId) return null;

    const key = cacheKey(inReplyToMessageId);
    const matchesId = msg => Number(msg.id) === key;
    const stub = (state = 'missing') => ({
      id: key,
      replyPreviewState: state,
    });

    const messageList = unref(messages) || [];
    const chat = unref(currentChat);

    let replyMessage = messageList.find(matchesId);

    if (!replyMessage && chat?.messages) {
      replyMessage = chat.messages.find(matchesId);
    }

    if (!replyMessage && fetchedReplyMessages.has(key)) {
      const cached = fetchedReplyMessages.get(key);
      if (cached) return cached;
      return stub(cached === null ? 'missing' : 'loading');
    }

    if (!replyMessage && chat?.id) {
      fetchReplyMessage(key, chat.id);
      return stub('loading');
    }

    if (!replyMessage) {
      return stub('missing');
    }

    return useCamelCase(replyMessage);
  };

  return {
    getInReplyToMessage,
    fetchReplyMessage,
    fetchedReplyMessages,
  };
};
