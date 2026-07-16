import { computed, unref } from 'vue';
import { useI18n } from 'vue-i18n';
import { MESSAGE_TYPE, ATTACHMENT_ICONS } from 'shared/constants/messages';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const attachmentIcons = {
  image: 'i-lucide-image',
  audio: 'i-lucide-headphones',
  video: 'i-lucide-video',
  file: 'i-lucide-file',
  location: 'i-lucide-map-pin',
  contact: 'i-lucide-contact',
  fallback: 'i-lucide-link-2',
};

export const getMessageBody = message => {
  if (!message) return '';

  const { content_attributes: contentAttributes } = message;
  const { email: { subject } = {} } = contentAttributes || {};

  return subject || message.content || message.processed_message_content || '';
};

export const getMessagePreviewText = (message, getPlainText) => {
  const body = getMessageBody(message);
  return body ? getPlainText(body) : '';
};

export const useMessagePreview = (
  messageSource,
  { showMessageType: showMessageTypeOption = true } = {}
) => {
  const { t } = useI18n();
  const { getPlainText } = useMessageFormatter();

  const message = computed(() => unref(messageSource));
  const showMessageType = computed(() => unref(showMessageTypeOption) ?? true);

  const messageByAgent = computed(
    () => message.value?.message_type === MESSAGE_TYPE.OUTGOING
  );

  const isMessageAnActivity = computed(
    () => message.value?.message_type === MESSAGE_TYPE.ACTIVITY
  );

  const isMessagePrivate = computed(() => message.value?.private);

  const parsedLastMessage = computed(() =>
    getMessagePreviewText(message.value, getPlainText)
  );

  const lastMessageFileType = computed(() => {
    const [{ file_type: fileType } = {}] = message.value?.attachments || [];
    return fileType;
  });

  const attachmentIconName = computed(
    () => ATTACHMENT_ICONS[lastMessageFileType.value]
  );

  const attachmentIconClass = computed(
    () => attachmentIcons[lastMessageFileType.value]
  );

  const attachmentMessageText = computed(() => {
    switch (lastMessageFileType.value) {
      case 'image':
        return t('CHAT_LIST.ATTACHMENTS.image.CONTENT');
      case 'audio':
        return t('CHAT_LIST.ATTACHMENTS.audio.CONTENT');
      case 'video':
        return t('CHAT_LIST.ATTACHMENTS.video.CONTENT');
      case 'file':
        return t('CHAT_LIST.ATTACHMENTS.file.CONTENT');
      case 'location':
        return t('CHAT_LIST.ATTACHMENTS.location.CONTENT');
      case 'contact':
        return t('CHAT_LIST.ATTACHMENTS.contact.CONTENT');
      default:
        return '';
    }
  });

  const lastMessageAttachmentId = computed(() => {
    const [{ id } = {}] = message.value?.attachments || [];
    return id ?? null;
  });

  const showAttachmentPreview = computed(() => {
    if (!message.value?.attachments?.length) return false;
    // FORK: share contact card
    if (lastMessageFileType.value === 'contact') return true;
    return !getMessageBody(message.value);
  });

  const isMessageSticker = computed(
    () => message.value?.content_type === 'sticker'
  );

  const hasPreviewText = computed(() => Boolean(getMessageBody(message.value)));

  return {
    message,
    showMessageType,
    messageByAgent,
    isMessageAnActivity,
    isMessagePrivate,
    parsedLastMessage,
    lastMessageFileType,
    lastMessageAttachmentId,
    attachmentIconName,
    attachmentIconClass,
    attachmentMessageText,
    showAttachmentPreview,
    isMessageSticker,
    hasPreviewText,
  };
};
