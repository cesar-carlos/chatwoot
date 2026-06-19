<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { getTieredSlaExample } from '../helpers/i18nHelper';

defineProps({
  showExample: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['create']);

const { tm } = useI18n();

const tieredSlaExample = computed(() => getTieredSlaExample(tm));
</script>

<template>
  <div
    class="flex flex-col items-center justify-center gap-6 py-16 px-6 text-center rounded-xl border border-dashed border-n-weak bg-n-solid-2"
  >
    <div
      class="size-14 rounded-full bg-n-alpha-2 flex items-center justify-center"
    >
      <span class="i-lucide-list-checks size-7 text-n-slate-10" />
    </div>
    <div class="flex flex-col gap-2 max-w-lg">
      <h3 class="text-base font-medium text-n-slate-12">
        {{ $t('CONVERSATION_RULES.EMPTY_STATE.TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11">
        {{ $t('CONVERSATION_RULES.EMPTY_STATE.DESCRIPTION') }}
      </p>
      <ul class="text-sm text-n-slate-11 text-left list-disc pl-5 space-y-1">
        <li>{{ $t('CONVERSATION_RULES.EMPTY_STATE.INACTIVITY') }}</li>
        <li>{{ $t('CONVERSATION_RULES.EMPTY_STATE.AGENT_NO_REPLY') }}</li>
        <li>{{ $t('CONVERSATION_RULES.EMPTY_STATE.CUSTOMER_NO_REPLY') }}</li>
        <li>{{ $t('CONVERSATION_RULES.EMPTY_STATE.FIRST_RESPONSE') }}</li>
      </ul>
      <div
        v-if="showExample"
        class="mt-2 p-3 rounded-lg bg-n-solid-1 border border-n-weak text-left"
      >
        <p class="text-xs font-medium text-n-slate-12 mb-1">
          {{ $t('CONVERSATION_RULES.FORM.TIERED_SLA_TITLE') }}
        </p>
        <ul class="text-xs text-n-slate-11 list-disc pl-4 space-y-0.5">
          <li v-for="(item, index) in tieredSlaExample" :key="index">
            {{ item }}
          </li>
        </ul>
      </div>
    </div>
    <Button
      :label="$t('CONVERSATION_RULES.ADD')"
      icon="i-lucide-plus"
      @click="$emit('create')"
    />
  </div>
</template>
