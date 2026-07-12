<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../provider.js';
import { useInbox } from 'dashboard/composables/useInbox';
import BaseBubble from './Base.vue';

// FORK: Evolution Go view-once unavailable media notice
const { inboxId, contentAttributes } = useMessageContext();

const {
  isAFacebookInbox,
  isAnInstagramChannel,
  isATiktokChannel,
  isAWhatsAppChannel,
} = useInbox(inboxId.value);

const unsupportedMessageKey = computed(() => {
  // FORK: Evolution Go view-once unavailable media notice
  if (contentAttributes.value?.unavailableType === 'view_once') {
    return 'CONVERSATION.VIEW_ONCE_MEDIA_UNAVAILABLE';
  }
  if (isAFacebookInbox.value)
    return 'CONVERSATION.UNSUPPORTED_MESSAGE_FACEBOOK';
  if (isAnInstagramChannel.value)
    return 'CONVERSATION.UNSUPPORTED_MESSAGE_INSTAGRAM';
  if (isATiktokChannel.value) return 'CONVERSATION.UNSUPPORTED_MESSAGE_TIKTOK';
  if (isAWhatsAppChannel.value)
    return 'CONVERSATION.UNSUPPORTED_MESSAGE_WHATSAPP';
  return 'CONVERSATION.UNSUPPORTED_MESSAGE';
});
</script>

<template>
  <BaseBubble class="px-4 py-3 text-sm" data-bubble-name="unsupported">
    {{ $t(unsupportedMessageKey) }}
  </BaseBubble>
</template>
