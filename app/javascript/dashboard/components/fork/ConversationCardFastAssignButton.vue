<!-- FORK: extracted for merge-safe fork integration -->
<script setup>
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

defineProps({
  chatId: {
    type: [String, Number],
    required: true,
  },
  assigneeId: {
    type: [String, Number],
    default: null,
  },
  show: {
    type: Boolean,
    default: false,
  },
  isAssignPending: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['fastAssign']);
</script>

<template>
  <button
    v-show="show"
    :key="`assign-btn-${chatId}-${assigneeId || 'unassigned'}`"
    v-tooltip.bottom="$t('CONVERSATION.FAST_ASSIGN')"
    type="button"
    class="mt-1 ltr:ml-auto rtl:mr-auto bg-n-slate-5 dark:bg-n-slate-7 text-n-slate-12 text-xxs px-1.5 py-0.5 rounded font-medium transition-all duration-200 hover:bg-n-slate-6 dark:hover:bg-n-slate-8"
    :class="{ 'opacity-70 pointer-events-none': isAssignPending }"
    :disabled="isAssignPending"
    :aria-label="$t('CONVERSATION.FAST_ASSIGN')"
    @click="emit('fastAssign', $event)"
  >
    <template v-if="isAssignPending">
      <Spinner
        :size="10"
        class="text-n-slate-12 ltr:mr-1 rtl:ml-1 inline-block"
      />
    </template>
    {{ $t('CONVERSATION.FAST_ASSIGN') }}
  </button>
</template>
