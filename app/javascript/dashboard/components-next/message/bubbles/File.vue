<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

import { useMessageContext } from '../provider.js';
import BaseAttachmentBubble from './BaseAttachment.vue';
import FileIcon from 'next/icon/FileIcon.vue';
// FORK: same-origin Active Storage download on alias hosts (dev-chat)
import { downloadFile } from 'customDashboard/helper/downloadFile';
// FORK: local download state for sequential print workflows
import { useAttachmentDownloadState } from 'customDashboard/composables/useAttachmentDownloadState';

const { attachments } = useMessageContext();

const { t } = useI18n();
const isDownloading = ref(false);
const {
  isDownloaded,
  downloadCount,
  isJustMarked,
  markDownloaded,
  markAsHandled,
  clearDownloaded,
} = useAttachmentDownloadState();

const attachment = computed(() => attachments.value[0]);

const url = computed(() => attachment.value?.dataUrl);

const fileName = computed(() => {
  if (url.value) {
    const filename = url.value.substring(url.value.lastIndexOf('/') + 1);
    return filename || t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  return t('CONVERSATION.UNKNOWN_FILE_TYPE');
});

const fileType = computed(() => {
  return fileName.value.split('.').pop();
});

const downloaded = computed(() => isDownloaded(attachment.value?.id));
const count = computed(() => downloadCount(attachment.value?.id));
const justMarked = computed(() => isJustMarked(attachment.value?.id));

const actionLabel = computed(() => {
  if (!downloaded.value) return t('CONVERSATION.DOWNLOAD');
  if (count.value <= 1) {
    return `${t('CONVERSATION.DOWNLOADED')} · ${t('CONVERSATION.DOWNLOAD_AGAIN')}`;
  }
  return `${t('CONVERSATION.DOWNLOADED_COUNT', { count: count.value })} · ${t('CONVERSATION.DOWNLOAD_AGAIN')}`;
});

const secondaryLabel = computed(() =>
  downloaded.value
    ? t('CONVERSATION.CLEAR_DOWNLOAD_MARK_SHORT')
    : t('CONVERSATION.MARK_AS_HANDLED_SHORT')
);

const onDownload = async () => {
  if (isDownloading.value || !attachment.value?.dataUrl) return;

  try {
    isDownloading.value = true;
    await downloadFile({
      url: attachment.value.dataUrl,
      type: attachment.value.fileType || 'file',
      extension: attachment.value.extension || fileType.value,
    });
    markDownloaded(attachment.value.id);
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.SHARED_FILES.DOWNLOAD_ERROR'));
  } finally {
    isDownloading.value = false;
  }
};

const onSecondaryAction = () => {
  if (!attachment.value?.id) return;
  if (downloaded.value) {
    clearDownloaded(attachment.value.id);
  } else {
    markAsHandled(attachment.value.id);
  }
};
</script>

<template>
  <BaseAttachmentBubble
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-n-alpha-3 dark:bg-n-alpha-white"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.FILE"
    :content="decodeURI(fileName)"
    :action="{
      onClick: onDownload,
      label: actionLabel,
      disabled: isDownloading,
      className: downloaded
        ? 'text-n-teal-11 border-n-teal-7 bg-n-teal-3/40'
        : '',
      badgeCount: count > 1 ? count : 0,
      justMarked,
    }"
    :secondary-action="{
      onClick: onSecondaryAction,
      label: secondaryLabel,
    }"
  >
    <template #icon>
      <FileIcon :file-type="fileType" class="size-4" />
    </template>
  </BaseAttachmentBubble>
</template>
