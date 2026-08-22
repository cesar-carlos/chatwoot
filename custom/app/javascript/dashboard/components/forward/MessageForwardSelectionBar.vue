<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMessageForwardSelection } from 'customDashboard/composables/useMessageForwardSelection';
import { MAX_FORWARD_MESSAGES } from 'customDashboard/composables/useMessageForward';

const { t } = useI18n();
const selection = useMessageForwardSelection();

const count = computed(() => selection?.selected.value.length || 0);
const canForward = computed(() => count.value > 0);
const isAtMax = computed(() => count.value >= MAX_FORWARD_MESSAGES);

const onForward = () => selection?.openForward();
const onCancel = () => selection?.exit();
</script>

<template>
  <div class="border-t border-n-strong bg-n-solid-2">
    <div class="flex items-center gap-2 px-3 py-2.5">
      <Button
        ghost
        slate
        sm
        icon="i-lucide-x"
        :label="t('CONVERSATION.FORWARD.CANCEL')"
        :aria-label="t('CONVERSATION.FORWARD.CANCEL')"
        class="flex-shrink-0"
        @click="onCancel"
      />
      <div class="flex min-w-0 flex-1 items-center gap-2">
        <span
          class="inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums"
          :class="
            isAtMax
              ? 'bg-n-amber-3 text-n-amber-11'
              : 'bg-n-alpha-2 text-n-slate-12 outline outline-1 outline-n-strong'
          "
        >
          {{ count }}/{{ MAX_FORWARD_MESSAGES }}
        </span>
        <span class="truncate text-sm text-n-slate-11">
          {{ t('CONVERSATION.FORWARD.SELECTED_COUNT', { count }) }}
        </span>
      </div>
      <Button
        sm
        blue
        solid
        icon="i-lucide-forward"
        :label="t('CONVERSATION.FORWARD.CONFIRM')"
        :disabled="!canForward"
        class="flex-shrink-0"
        @click="onForward"
      />
    </div>
    <p class="pb-2 text-center text-xs text-n-slate-9">
      {{ t('CONVERSATION.FORWARD.SHIFT_HINT') }}
    </p>
  </div>
</template>
