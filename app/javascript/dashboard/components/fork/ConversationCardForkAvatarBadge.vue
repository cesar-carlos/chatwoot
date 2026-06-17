<!-- FORK: extracted for merge-safe fork integration -->
<script setup>
import UnreadCountBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadCountBadge.vue';

defineProps({
  count: {
    type: Number,
    default: 0,
  },
  hideThumbnail: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <UnreadCountBadge
    v-if="!hideThumbnail"
    :count="count"
    class="absolute z-20 -top-1 ltr:-left-1 rtl:-right-1"
  />
</template>
