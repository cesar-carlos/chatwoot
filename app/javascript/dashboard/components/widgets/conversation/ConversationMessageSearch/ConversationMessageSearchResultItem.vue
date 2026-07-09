<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { ATTACHMENT_TYPES } from 'dashboard/components-next/message/constants.js';
import { readTranscriptText } from 'dashboard/composables/fork/useTranscriptText';
import { textIncludesFoldedQuery } from 'dashboard/composables/fork/messageSearchText';
import { buildSearchResultDisplayMessage } from 'dashboard/composables/fork/conversationMessageSearchDisplay';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import AudioChip from 'next/message/chips/Audio.vue';
import MessageContent from 'dashboard/modules/search/components/MessageContent.vue';
import TranscribedText from 'dashboard/modules/search/components/TranscribedText.vue';

const props = defineProps({
  id: {
    type: String,
    default: '',
  },
  message: {
    type: Object,
    required: true,
  },
  searchQuery: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  active: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const audioAttachment = computed(() =>
  props.message.attachments?.find(
    attachment =>
      attachment.file_type === ATTACHMENT_TYPES.AUDIO ||
      attachment.fileType === ATTACHMENT_TYPES.AUDIO
  )
);

const transcriptText = computed(() =>
  readTranscriptText(audioAttachment.value)
);

const displayAudioAttachment = computed(() => {
  if (!audioAttachment.value) return null;
  return useCamelCase(audioAttachment.value, { deep: true });
});

const isTranscriptionMatch = computed(() => {
  if (props.message.matched_on === 'transcription') return true;

  return textIncludesFoldedQuery(transcriptText.value, props.searchQuery);
});

const contentMatchesQuery = computed(() => {
  if (props.message.matched_on === 'content') return true;

  return (
    textIncludesFoldedQuery(props.message.content, props.searchQuery) ||
    textIncludesFoldedQuery(
      props.message.content_attributes?.email?.subject,
      props.searchQuery
    )
  );
});

const displayMessage = computed(() =>
  buildSearchResultDisplayMessage({
    message: props.message,
    searchQuery: props.searchQuery,
    transcriptText: transcriptText.value,
  })
);

const authorName = computed(() => {
  const { sender } = props.message;
  return sender?.name || t('SEARCH.BOT_LABEL');
});

const createdAtTime = computed(() => {
  if (!props.message.created_at) return '';
  return dynamicTime(props.message.created_at);
});

const openResultLabel = computed(() =>
  t('CONVERSATION.MESSAGE_SEARCH.OPEN_RESULT', {
    author: authorName.value,
    time: createdAtTime.value,
  })
);

const handleSelect = () => {
  if (props.disabled) return;
  emit('select', props.message);
};
</script>

<template>
  <button
    :id="id"
    type="button"
    role="option"
    class="w-full text-start rounded-xl border px-4 py-3 cursor-pointer hover:bg-n-slate-2 dark:hover:bg-n-solid-3 disabled:cursor-not-allowed disabled:opacity-60"
    :class="
      active ? 'border-n-brand bg-n-brand/5' : 'border-n-weak bg-n-solid-1'
    "
    :aria-label="openResultLabel"
    :aria-selected="active"
    :disabled="disabled"
    @click="handleSelect"
  >
    <div class="flex items-center justify-between gap-2 mb-1">
      <div
        v-if="message.private"
        class="flex items-center gap-1.5 text-n-amber-11"
      >
        <Icon icon="i-lucide-lock-keyhole" class="size-3.5 flex-shrink-0" />
        <span class="text-sm leading-4">
          {{ t('CONVERSATION.MESSAGE_SEARCH.PRIVATE_NOTE') }}
        </span>
      </div>
      <span
        v-if="createdAtTime"
        class="text-sm text-n-slate-11 flex-shrink-0 ltr:ml-auto rtl:mr-auto"
      >
        {{ createdAtTime }}
      </span>
    </div>

    <MessageContent
      :author="authorName"
      :message="displayMessage"
      :search-term="searchQuery"
    />

    <div v-if="displayAudioAttachment" class="mt-1.5 w-full">
      <AudioChip
        class="bg-n-alpha-2 dark:bg-n-alpha-2 text-n-slate-12"
        :attachment="displayAudioAttachment"
        :show-transcribed-text="false"
        @click.prevent
      />
      <div
        v-if="transcriptText && (contentMatchesQuery || !isTranscriptionMatch)"
        class="pt-2"
      >
        <TranscribedText :text="transcriptText" :search-term="searchQuery" />
      </div>
    </div>

    <div
      v-if="isTranscriptionMatch"
      class="flex items-center gap-1.5 mt-2 text-xs text-n-slate-11"
    >
      <Icon icon="i-lucide-mic" class="size-3.5 flex-shrink-0" />
      <span>{{ t('CONVERSATION.MESSAGE_SEARCH.MATCH_TRANSCRIPTION') }}</span>
    </div>
  </button>
</template>
