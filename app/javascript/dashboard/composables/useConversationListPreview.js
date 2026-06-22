import { computed, unref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import { getMessagePreviewText } from 'shared/composables/useMessagePreview';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const conversationCustomAttributes = conversation => {
  return (
    conversation?.custom_attributes || conversation?.customAttributes || {}
  );
};

export const useConversationListPreview = conversationSource => {
  const { t } = useI18n();
  const { getPlainText } = useMessageFormatter();

  return computed(() => {
    const conversation = unref(conversationSource);
    if (!conversation) return t('CHAT_LIST.NO_CONTENT');

    const { email: { subject } = {} } =
      conversationCustomAttributes(conversation);
    if (subject) return getPlainText(subject);

    const previewText = getMessagePreviewText(
      getLastMessage(conversation),
      getPlainText
    );

    return previewText || t('CHAT_LIST.NO_CONTENT');
  });
};
