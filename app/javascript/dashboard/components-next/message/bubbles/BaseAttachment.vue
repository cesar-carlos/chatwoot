<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../provider.js';

const props = defineProps({
  icon: { type: [String, Object], required: true },
  iconBgColor: { type: String, default: 'bg-n-alpha-3' },
  senderTranslationKey: { type: String, default: '' }, // FORK: share contact card
  content: { type: String, required: true },
  title: { type: String, default: '' }, // Title can be any name, description, etc
  action: {
    type: Object,
    default: null,
    validator: action => {
      if (!action) return true;
      return action.label && (action.href || action.onClick);
    },
  },
});

const { sender } = useMessageContext();
const { t } = useI18n();

const senderName = computed(() => {
  return sender?.value?.name || '';
});

const senderLabel = computed(() => {
  if (!props.senderTranslationKey) return '';

  switch (props.senderTranslationKey) {
    case 'CONVERSATION.SHARED_ATTACHMENT.CONTACT_OUTGOING':
      return t('CONVERSATION.SHARED_ATTACHMENT.CONTACT_OUTGOING');
    case 'CONVERSATION.SHARED_ATTACHMENT.CONTACT':
      if (!senderName.value) return '';

      return t('CONVERSATION.SHARED_ATTACHMENT.CONTACT', {
        sender: senderName.value,
      });
    case 'CONVERSATION.SHARED_ATTACHMENT.FILE':
      return t('CONVERSATION.SHARED_ATTACHMENT.FILE', {
        sender: senderName.value,
      });
    case 'CONVERSATION.SHARED_ATTACHMENT.LOCATION':
      return t('CONVERSATION.SHARED_ATTACHMENT.LOCATION', {
        sender: senderName.value,
      });
    case 'CONVERSATION.SHARED_ATTACHMENT.MEETING':
      return t('CONVERSATION.SHARED_ATTACHMENT.MEETING', {
        sender: senderName.value,
      });
    default:
      return '';
  }
});
</script>

<template>
  <BaseBubble class="overflow-hidden p-3" data-bubble-name="attachment">
    <div class="grid gap-4 min-w-64">
      <div class="grid gap-3">
        <div
          class="size-8 rounded-lg grid place-content-center"
          :class="iconBgColor"
        >
          <slot name="icon">
            <Icon :icon="icon" class="text-white size-4" />
          </slot>
        </div>
        <div class="space-y-1 overflow-hidden">
          <div v-if="senderLabel" class="text-n-slate-12 text-sm truncate">
            {{ senderLabel }}
          </div>
          <slot>
            <div v-if="title" class="truncate text-sm text-n-slate-12">
              {{ title }}
            </div>
            <div v-if="content" class="truncate text-sm text-n-slate-11">
              {{ content }}
            </div>
          </slot>
        </div>
      </div>
      <div v-if="action" class="mb-2">
        <a
          v-if="action.href"
          :href="action.href"
          rel="noreferrer noopener nofollow"
          target="_blank"
          class="w-full block bg-n-solid-3 px-4 py-2 rounded-lg text-sm text-center border border-n-container"
        >
          {{ action.label }}
        </a>
        <button
          v-else
          class="w-full bg-n-solid-3 px-4 py-2 rounded-lg text-sm text-center border border-n-container"
          @click="action.onClick"
        >
          {{ action.label }}
        </button>
      </div>
    </div>
  </BaseBubble>
</template>
