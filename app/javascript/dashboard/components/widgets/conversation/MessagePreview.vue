<script setup>
import { toRef } from 'vue';
import { useMessagePreview } from 'shared/composables/useMessagePreview';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
  showMessageType: {
    type: Boolean,
    default: true,
  },
  defaultEmptyMessage: {
    type: String,
    default: '',
  },
});

const {
  showMessageType,
  messageByAgent,
  isMessageAnActivity,
  isMessagePrivate,
  parsedLastMessage,
  lastMessageFileType,
  attachmentIconName,
  attachmentMessageText,
  showAttachmentPreview,
  isMessageSticker,
  hasPreviewText,
} = useMessagePreview(toRef(props, 'message'), {
  showMessageType: toRef(props, 'showMessageType'),
});
</script>

<template>
  <div class="overflow-hidden text-ellipsis whitespace-nowrap">
    <template v-if="showMessageType">
      <fluent-icon
        v-if="isMessagePrivate"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="lock-closed"
      />
      <fluent-icon
        v-else-if="messageByAgent"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="arrow-reply"
      />
      <fluent-icon
        v-else-if="isMessageAnActivity"
        size="16"
        class="-mt-0.5 align-middle text-n-slate-11 inline-block"
        icon="info"
      />
    </template>
    <span v-if="hasPreviewText && isMessageSticker">
      <fluent-icon
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        icon="image"
      />
      {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
    </span>
    <span v-else-if="hasPreviewText && lastMessageFileType !== 'contact'">
      {{ parsedLastMessage }}
    </span>
    <span v-else-if="showAttachmentPreview">
      <fluent-icon
        v-if="attachmentIconName && showMessageType"
        size="16"
        class="-mt-0.5 align-middle inline-block text-n-slate-11"
        :icon="attachmentIconName"
      />
      {{ attachmentMessageText }}
    </span>
    <span v-else>
      {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
    </span>
  </div>
</template>
