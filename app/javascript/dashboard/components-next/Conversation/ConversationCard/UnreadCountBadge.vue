<script setup>
import { computed } from 'vue';

const props = defineProps({
  count: {
    type: [Number, String],
    default: 0,
  },
});

const safeCount = computed(() => {
  const parsedCount = Number(props.count);
  if (Number.isNaN(parsedCount) || parsedCount <= 0) {
    return 0;
  }

  return Math.floor(parsedCount);
});

const label = computed(() => (safeCount.value > 9 ? '9+' : safeCount.value));
</script>

<template>
  <span
    v-if="safeCount > 0"
    class="inline-flex items-center justify-center h-4 px-1 text-white rounded-full min-w-4 bg-n-brand text-xxs font-semibold shadow-lg pointer-events-none"
  >
    {{ label }}
  </span>
  <span v-else />
</template>
