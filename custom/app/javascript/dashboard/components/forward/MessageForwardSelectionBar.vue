<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useMessageForwardSelection } from 'customDashboard/composables/useMessageForwardSelection';

const { t } = useI18n();
const selection = useMessageForwardSelection();

const count = computed(() => selection?.selected.value.length || 0);
const canForward = computed(() => count.value > 0);

const selectedCountLabel = computed(() =>
  t('CONVERSATION.FORWARD.SELECTED_COUNT', { count: count.value })
);

const onForward = () => {
  selection?.openForward();
};

const onCancel = () => {
  selection?.exit();
};
</script>

<template>
  <div
    class="flex items-center gap-3 border-t border-n-strong bg-n-solid-2 px-4 py-2"
  >
    <Button
      ghost
      slate
      sm
      icon="i-lucide-x"
      :title="$t('CONVERSATION.FORWARD.CANCEL')"
      :aria-label="$t('CONVERSATION.FORWARD.CANCEL')"
      @click="onCancel"
    />
    <p class="min-w-0 flex-1 truncate text-sm font-medium text-n-slate-12">
      {{ selectedCountLabel }}
    </p>
    <Button
      sm
      blue
      solid
      icon="i-lucide-forward"
      :label="$t('CONVERSATION.FORWARD.CONFIRM')"
      :disabled="!canForward"
      @click="onForward"
    />
  </div>
</template>
