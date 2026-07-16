<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getFileInfo } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
// FORK: same-origin Active Storage download on alias hosts (dev-chat)
import { downloadFile } from 'customDashboard/helper/downloadFile';
// FORK: local download state for sequential print workflows
import { useAttachmentDownloadState } from 'customDashboard/composables/useAttachmentDownloadState';

import FileIcon from 'next/icon/FileIcon.vue';
import Icon from 'next/icon/Icon.vue';

const { attachment } = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const isDownloading = ref(false);
const {
  isDownloaded,
  downloadCount,
  isJustMarked,
  markDownloaded,
  markAsHandled,
  clearDownloaded,
  downloadActionTooltip,
  contextActionTooltip,
} = useAttachmentDownloadState();

const fileDetails = computed(() => {
  return getFileInfo(attachment?.dataUrl || '');
});

const downloaded = computed(() => isDownloaded(attachment?.id));
const count = computed(() => downloadCount(attachment?.id));
const justMarked = computed(() => isJustMarked(attachment?.id));

const downloadTooltip = computed(() =>
  downloadActionTooltip(t, attachment?.id, 'CONVERSATION')
);

const contextTooltip = computed(() =>
  contextActionTooltip(t, attachment?.id, 'CONVERSATION')
);

const displayFileName = computed(() => {
  const { base, type } = fileDetails.value;
  const truncatedName = (str, maxLength, hasExt) =>
    str.length > maxLength
      ? `${str.substring(0, maxLength).trimEnd()}${hasExt ? '..' : '...'}`
      : str;

  return type
    ? `${truncatedName(base, 12, true)}.${type}`
    : truncatedName(base, 14, false);
});

const textColorClass = computed(() => {
  const colorMap = {
    '7z': 'dark:text-[#EDEEF0] text-[#2F265F]',
    csv: 'text-n-amber-12',
    doc: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    docx: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    json: 'text-n-slate-12',
    odt: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    pdf: 'text-n-slate-12',
    ppt: 'dark:text-[#FFE0C2] text-[#582D1D]',
    pptx: 'dark:text-[#FFE0C2] text-[#582D1D]',
    rar: 'dark:text-[#EDEEF0] text-[#2F265F]',
    rtf: 'dark:text-[#D6E1FF] text-[#1F2D5C]', // indigo-12
    tar: 'dark:text-[#EDEEF0] text-[#2F265F]',
    txt: 'text-n-slate-12',
    xls: 'text-n-teal-12',
    xlsx: 'text-n-teal-12',
    zip: 'dark:text-[#EDEEF0] text-[#2F265F]',
  };

  return colorMap[fileDetails.value.type] || 'text-n-slate-12';
});

const onDownload = async () => {
  if (isDownloading.value || !attachment?.dataUrl) return;

  try {
    isDownloading.value = true;
    await downloadFile({
      url: attachment.dataUrl,
      type: attachment.fileType || 'file',
      extension: attachment.extension || fileDetails.value.type,
    });
    markDownloaded(attachment.id);
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.SHARED_FILES.DOWNLOAD_ERROR'));
  } finally {
    isDownloading.value = false;
  }
};

const onContextAction = event => {
  event.preventDefault();
  if (!attachment?.id) return;

  if (downloaded.value) {
    clearDownloaded(attachment.id);
  } else {
    markAsHandled(attachment.id);
  }
};
</script>

<template>
  <div
    class="h-9 bg-n-alpha-white gap-2 overflow-hidden items-center flex px-2 rounded-lg border border-n-container transition-opacity"
    :class="{ 'opacity-80': downloaded }"
    :title="contextTooltip"
    @contextmenu="onContextAction"
  >
    <FileIcon class="flex-shrink-0" :file-type="fileDetails.type" />
    <span
      class="flex-1 min-w-0 text-sm max-w-36"
      :title="fileDetails.name"
      :class="textColorClass"
    >
      {{ displayFileName }}
    </span>
    <button
      v-tooltip="downloadTooltip"
      type="button"
      class="relative flex-shrink-0 size-9 grid place-content-center cursor-pointer transition-all disabled:opacity-50"
      :class="[
        downloaded
          ? 'text-n-teal-11 hover:text-n-teal-12'
          : 'text-n-slate-11 hover:text-n-slate-12',
        justMarked ? 'scale-125' : 'scale-100',
      ]"
      :aria-label="downloadTooltip"
      :disabled="isDownloading"
      @click.stop="onDownload"
      @contextmenu.stop="onContextAction"
    >
      <Icon
        :icon="downloaded ? 'i-lucide-check' : 'i-lucide-download'"
        class="transition-transform duration-200"
        :class="{ 'animate-pulse': isDownloading }"
      />
      <span
        v-if="count > 1"
        class="absolute -top-0.5 -end-0.5 min-w-3.5 h-3.5 px-0.5 rounded-full bg-n-teal-9 text-white text-[10px] leading-3.5 text-center font-medium tabular-nums"
      >
        {{ count > 99 ? '99+' : count }}
      </span>
    </button>
  </div>
</template>
