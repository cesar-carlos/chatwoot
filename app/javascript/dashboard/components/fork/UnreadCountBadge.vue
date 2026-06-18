<!-- FORK: extracted for merge-safe fork integration -->
<script setup>
import { computed } from 'vue';
import { formatConversationUnreadBadgeLabel } from 'dashboard/composables/fork/normalizeUnreadCount';

const props = defineProps({
  count: {
    type: Number,
    default: 0,
  },
});

const label = computed(() => formatConversationUnreadBadgeLabel(props.count));
</script>

<template>
  <span
    v-if="label"
    data-test-id="conversation-unread-badge"
    class="inline-flex items-center justify-center h-4 px-1 text-white rounded-full min-w-4 bg-n-brand text-xxs font-semibold shadow-lg pointer-events-none"
  >
    {{ label }}
  </span>
</template>
