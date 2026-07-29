<!-- FORK: custom role team permission normalization - team on conversation card -->
<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  team: {
    type: Object,
    default: null,
  },
  variant: {
    type: String,
    default: 'label',
    validator: value => ['label', 'icon'].includes(value),
  },
});

const { t } = useI18n();

const teamName = computed(() => props.team?.name || '');

const tooltipContent = computed(() =>
  teamName.value
    ? t('CHAT_LIST.CARD.TEAM_TOOLTIP', { name: teamName.value })
    : ''
);

const show = computed(() => Boolean(teamName.value));
</script>

<template>
  <span
    v-if="show && variant === 'label'"
    v-tooltip.top="tooltipContent"
    class="text-n-slate-11 text-xs font-medium leading-3 py-0.5 px-0 inline-flex items-center gap-0.5 max-w-[8rem] truncate"
  >
    <fluent-icon icon="people-team" size="12" class="flex-shrink-0 text-n-slate-11" />
    <span class="truncate">{{ teamName }}</span>
  </span>
  <span
    v-else-if="show && variant === 'icon'"
    v-tooltip.top="tooltipContent"
    class="flex items-center justify-center flex-shrink-0 size-4"
  >
    <Icon icon="i-lucide-users" class="size-3.5 text-n-slate-10" />
  </span>
</template>
