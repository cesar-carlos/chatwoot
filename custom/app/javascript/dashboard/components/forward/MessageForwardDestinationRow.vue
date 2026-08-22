<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  item: {
    type: Object,
    required: true,
  },
  selected: {
    type: Boolean,
    default: false,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);
const { t } = useI18n();

const onActivate = () => {
  if (props.disabled && !props.selected) return;
  emit('toggle', props.item);
};
</script>

<template>
  <div
    role="option"
    :aria-selected="selected"
    :tabindex="disabled && !selected ? -1 : 0"
    class="flex items-center gap-2.5 rounded-lg px-2 py-2 text-left transition-colors"
    :class="
      selected
        ? 'bg-n-brand/10 outline outline-1 -outline-offset-1 outline-n-brand/40'
        : disabled
          ? 'cursor-not-allowed opacity-40'
          : 'cursor-pointer hover:bg-n-alpha-2'
    "
    @click="onActivate"
    @keydown.enter.prevent="onActivate"
  >
    <Checkbox :model-value="selected" class="pointer-events-none shrink-0" />
    <Avatar :name="item.label" :src="item.thumbnail" :size="32" rounded-full />
    <div class="min-w-0 flex-1">
      <div class="flex items-center gap-1.5">
        <span class="truncate text-sm font-medium text-n-slate-12">
          {{ item.label }}
        </span>
        <span
          v-if="item.conversationStatus === 'open'"
          class="shrink-0 rounded-full bg-n-teal-3 px-1.5 py-0.5 text-[10px] font-medium text-n-teal-11"
        >
          {{ t('CONVERSATION.FORWARD.STATUS_OPEN') }}
        </span>
        <span
          v-else-if="item.conversationStatus === 'pending'"
          class="shrink-0 rounded-full bg-n-amber-3 px-1.5 py-0.5 text-[10px] font-medium text-n-amber-11"
        >
          {{ t('CONVERSATION.FORWARD.STATUS_PENDING') }}
        </span>
        <span
          v-else-if="item.kind === 'conversation'"
          class="shrink-0 rounded-full bg-n-teal-3 px-1.5 py-0.5 text-[10px] font-medium text-n-teal-11"
        >
          {{ t('CONVERSATION.FORWARD.HAS_CONVERSATION') }}
        </span>
      </div>
      <div v-if="item.phoneNumber" class="truncate text-xs text-n-slate-10">
        {{ item.phoneNumber }}
      </div>
    </div>
  </div>
</template>
