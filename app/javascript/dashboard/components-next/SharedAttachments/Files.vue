<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { formatBytes } from 'shared/helpers/FileHelper';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';
// FORK: same-origin Active Storage download on alias hosts (dev-chat)
import { downloadFile } from 'customDashboard/helper/downloadFile';
// FORK: local download state for sequential print workflows
import { useAttachmentDownloadState } from 'customDashboard/composables/useAttachmentDownloadState';
import {
  MEDIA_TYPES,
  NON_FILE_TYPES,
} from 'dashboard/components-next/message/constants';

import FileIcon from 'next/icon/FileIcon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const FILTERS = {
  ALL: 'all',
  PENDING: 'pending',
  DOWNLOADED: 'downloaded',
};

const props = defineProps({
  attachments: { type: Array, default: () => [] },
  peekLimit: { type: Number, default: 0 },
  showJumpToMessage: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'jumpToMessage']);

const { t } = useI18n();
const {
  isDownloaded,
  downloadCount,
  markDownloaded,
  markAsHandled,
  clearDownloaded,
  downloadActionTooltip,
  contextActionTooltip,
} = useAttachmentDownloadState();

const fileAttachments = computed(() =>
  [...props.attachments]
    .filter(
      a =>
        a.data_url &&
        !MEDIA_TYPES.includes(a.file_type) &&
        !NON_FILE_TYPES.includes(a.file_type)
    )
    .sort((a, b) => (b.created_at || 0) - (a.created_at || 0))
);

const showAll = ref(false);
const downloadingId = ref(null);
const activeFilter = ref(FILTERS.ALL);

const isPeekable = computed(() => props.peekLimit > 0);

const downloadedCount = computed(
  () => fileAttachments.value.filter(a => isDownloaded(a.id)).length
);

const filteredFiles = computed(() => {
  if (activeFilter.value === FILTERS.PENDING) {
    return fileAttachments.value.filter(a => !isDownloaded(a.id));
  }
  if (activeFilter.value === FILTERS.DOWNLOADED) {
    return fileAttachments.value.filter(a => isDownloaded(a.id));
  }
  return fileAttachments.value;
});

const visibleFiles = computed(() => {
  if (!isPeekable.value || showAll.value) return filteredFiles.value;
  return filteredFiles.value.slice(0, props.peekLimit);
});

const fileNameFromUrl = url => {
  if (!url) return '';
  const name = url.split('/').pop();
  return name ? decodeURIComponent(name) : '';
};

const displayName = attachment =>
  fileNameFromUrl(attachment.data_url) ||
  t('CONVERSATION_SIDEBAR.SHARED_FILES.UNTITLED_FILE');

const displaySize = attachment => {
  if (attachment.file_size) return formatBytes(attachment.file_size);
  if (attachment.extension) return attachment.extension.toUpperCase();
  return '—';
};

const displayTime = attachment => {
  if (!attachment.created_at) return '';
  return shortTimestamp(dynamicTime(attachment.created_at), true);
};

const onActivate = attachment => emit('select', attachment);

const filterLabel = filter => {
  if (filter === FILTERS.PENDING) {
    return t('CONVERSATION_SIDEBAR.SHARED_FILES.FILTER_PENDING');
  }
  if (filter === FILTERS.DOWNLOADED) {
    return t('CONVERSATION_SIDEBAR.SHARED_FILES.FILTER_DOWNLOADED');
  }
  return t('CONVERSATION_SIDEBAR.SHARED_FILES.FILTER_ALL');
};

const onDownloadFile = async attachment => {
  const { id, file_type: type, data_url: url, extension } = attachment;
  try {
    downloadingId.value = id;
    await downloadFile({ url, type, extension });
    markDownloaded(id);
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.SHARED_FILES.DOWNLOAD_ERROR'));
  } finally {
    downloadingId.value = null;
  }
};

const onContextAction = (event, attachment) => {
  event.preventDefault();
  if (!attachment?.id) return;
  if (isDownloaded(attachment.id)) {
    clearDownloaded(attachment.id);
  } else {
    markAsHandled(attachment.id);
  }
};
</script>

<template>
  <section v-if="fileAttachments.length" class="flex flex-col gap-2.5">
    <header class="flex flex-col gap-2 px-0.5">
      <div class="flex items-center justify-between">
        <h4
          class="text-xs font-semibold tracking-wider uppercase text-n-slate-11"
        >
          {{ t('CONVERSATION_SIDEBAR.SHARED_FILES.FILES_HEADING') }}
          <span
            class="ms-1 font-medium tracking-normal normal-case text-n-slate-10"
          >
            {{
              t('CONVERSATION_SIDEBAR.SHARED_FILES.DOWNLOAD_PROGRESS', {
                downloaded: downloadedCount,
                total: fileAttachments.length,
              })
            }}
          </span>
        </h4>
        <NextButton
          v-if="isPeekable && filteredFiles.length > peekLimit"
          ghost
          slate
          xs
          trailing-icon
          :icon="showAll ? 'i-lucide-chevron-up' : 'i-lucide-chevron-right'"
          :label="
            showAll
              ? t('CONVERSATION_SIDEBAR.SHARED_FILES.SHOW_LESS')
              : t('CONVERSATION_SIDEBAR.SHARED_FILES.VIEW_ALL')
          "
          @click="showAll = !showAll"
        />
      </div>
      <div class="flex items-center gap-1">
        <button
          v-for="filter in [FILTERS.ALL, FILTERS.PENDING, FILTERS.DOWNLOADED]"
          :key="filter"
          type="button"
          class="px-2 py-0.5 rounded-md text-xs transition-colors"
          :class="
            activeFilter === filter
              ? 'bg-n-solid-3 text-n-slate-12'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-2'
          "
          @click="activeFilter = filter"
        >
          {{ filterLabel(filter) }}
        </button>
      </div>
    </header>
    <ul class="flex flex-col gap-0.5">
      <li
        v-for="attachment in visibleFiles"
        :key="attachment.id"
        role="button"
        tabindex="0"
        class="flex items-center gap-3 px-2 py-2 transition-colors rounded-lg cursor-pointer hover:bg-n-slate-3 group focus:outline-none focus-visible:ring-2 focus-visible:ring-n-blue-9"
        :class="{ 'opacity-80': isDownloaded(attachment.id) }"
        :title="
          contextActionTooltip(
            t,
            attachment.id,
            'CONVERSATION_SIDEBAR.SHARED_FILES'
          )
        "
        @click="onActivate(attachment)"
        @keydown.enter="onActivate(attachment)"
        @keydown.space.prevent="onActivate(attachment)"
        @contextmenu="onContextAction($event, attachment)"
      >
        <div
          class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-gradient-to-br from-n-slate-3 to-n-slate-4 ring-1 ring-inset ring-n-slate-4/40"
        >
          <FileIcon
            :file-type="attachment.extension?.toLowerCase() || ''"
            class="size-4 text-n-slate-11"
          />
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium truncate text-n-slate-12 mb-1">
            {{ displayName(attachment) }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ displaySize(attachment) }}
            <template v-if="displayTime(attachment)">
              · {{ displayTime(attachment) }}
            </template>
          </p>
        </div>
        <div class="flex items-center gap-1">
          <NextButton
            v-if="showJumpToMessage && attachment.message_id"
            v-tooltip.top="{
              content: t('CONVERSATION_SIDEBAR.SHARED_FILES.JUMP_TO_MESSAGE'),
              delay: { show: 500, hide: 0 },
            }"
            ghost
            slate
            sm
            icon="i-lucide-external-link"
            class="opacity-0 group-hover:opacity-100"
            :aria-label="t('CONVERSATION_SIDEBAR.SHARED_FILES.JUMP_TO_MESSAGE')"
            @click.stop="emit('jumpToMessage', attachment)"
            @keydown.enter.stop
            @keydown.space.stop
          />
          <div
            class="inline-flex items-center gap-1"
            :class="{
              'opacity-100': isDownloaded(attachment.id),
              'opacity-0 group-hover:opacity-100': !isDownloaded(attachment.id),
            }"
          >
            <NextButton
              v-tooltip.top="{
                content: downloadActionTooltip(
                  t,
                  attachment.id,
                  'CONVERSATION_SIDEBAR.SHARED_FILES'
                ),
                delay: { show: 500, hide: 0 },
              }"
              ghost
              slate
              sm
              :icon="
                isDownloaded(attachment.id)
                  ? 'i-lucide-check'
                  : 'i-lucide-download'
              "
              :class="{
                'text-n-teal-11': isDownloaded(attachment.id),
              }"
              :is-loading="downloadingId === attachment.id"
              :aria-label="
                downloadActionTooltip(
                  t,
                  attachment.id,
                  'CONVERSATION_SIDEBAR.SHARED_FILES'
                )
              "
              @click.stop="onDownloadFile(attachment)"
              @contextmenu.stop="onContextAction($event, attachment)"
              @keydown.enter.stop
              @keydown.space.stop
            />
            <span
              v-if="downloadCount(attachment.id) > 1"
              class="min-w-4 h-4 px-1 rounded-full bg-n-teal-9 text-white text-[10px] leading-4 text-center font-medium tabular-nums"
            >
              {{
                downloadCount(attachment.id) > 99
                  ? '99+'
                  : downloadCount(attachment.id)
              }}
            </span>
          </div>
        </div>
      </li>
    </ul>
  </section>
  <template v-else />
</template>
