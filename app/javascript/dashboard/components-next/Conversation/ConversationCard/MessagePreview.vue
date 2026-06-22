<script setup>
import { toRef } from 'vue';
import { useMessagePreview } from 'shared/composables/useMessagePreview';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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
  multiLine: {
    type: Boolean,
    default: false,
  },
});

const {
  showMessageType,
  messageByAgent,
  isMessageAnActivity,
  isMessagePrivate,
  parsedLastMessage,
  lastMessageFileType,
  attachmentIconClass,
  attachmentMessageText,
  showAttachmentPreview,
  isMessageSticker,
  hasPreviewText,
} = useMessagePreview(toRef(props, 'message'), {
  showMessageType: toRef(props, 'showMessageType'),
});
</script>

<template>
  <div
    class="min-w-0 text-sm"
    :class="
      multiLine
        ? 'flex items-start gap-1'
        : 'grid grid-cols-[auto_1fr] items-center gap-1'
    "
  >
    <template v-if="showMessageType && !multiLine">
      <Icon
        v-if="isMessagePrivate"
        icon="i-lucide-lock-keyhole"
        class="size-3.5"
      />
      <Icon
        v-else-if="messageByAgent"
        icon="i-lucide-undo-2"
        class="size-3.5"
      />
      <Icon
        v-else-if="isMessageAnActivity"
        icon="i-lucide-info"
        class="size-3.5"
      />
    </template>

    <span
      class="min-w-0 text-body-main"
      :class="multiLine ? 'line-clamp-2' : 'truncate'"
    >
      <template v-if="showMessageType && multiLine">
        <Icon
          v-if="isMessagePrivate"
          icon="i-lucide-lock-keyhole"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
        <Icon
          v-else-if="messageByAgent"
          icon="i-lucide-undo-2"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
        <Icon
          v-else-if="isMessageAnActivity"
          icon="i-lucide-info"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
      </template>
      <span
        v-if="hasPreviewText && isMessageSticker"
        class="inline-grid grid-flow-col auto-cols-max items-center gap-1"
      >
        <Icon icon="i-lucide-image" class="size-3.5" />
        {{ $t('CHAT_LIST.ATTACHMENTS.image.CONTENT') }}
      </span>

      <template v-else-if="hasPreviewText && lastMessageFileType !== 'contact'">
        {{ parsedLastMessage }}
      </template>

      <span
        v-else-if="showAttachmentPreview"
        class="inline-block align-middle truncate"
      >
        <Icon
          v-if="attachmentIconClass && showMessageType"
          :icon="attachmentIconClass"
          class="inline-block align-middle size-3.5 ltr:mr-1 rtl:ml-1"
        />
        <span class="inline-block align-middle">
          {{ attachmentMessageText }}
        </span>
      </span>

      <template v-else>
        {{ defaultEmptyMessage || $t('CHAT_LIST.NO_CONTENT') }}
      </template>
    </span>
  </div>
</template>
