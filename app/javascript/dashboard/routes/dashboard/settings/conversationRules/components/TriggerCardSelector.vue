<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  triggers: {
    type: Array,
    required: true,
  },
  modelValue: {
    type: String,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const selectTrigger = key => {
  emit('update:modelValue', key);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ $t('CONVERSATION_RULES.FORM.TRIGGER') }}
    </span>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
      <button
        v-for="trigger in triggers"
        :key="trigger.key"
        type="button"
        class="flex flex-col gap-1.5 p-3 rounded-lg border text-left transition-colors"
        :class="
          modelValue === trigger.key
            ? 'border-n-brand bg-n-brand/5 ring-1 ring-n-brand'
            : 'border-n-weak bg-n-solid-2 hover:border-n-slate-8'
        "
        @click="selectTrigger(trigger.key)"
      >
        <div class="flex items-center gap-2">
          <span
            class="size-8 rounded-full bg-n-alpha-2 flex items-center justify-center shrink-0"
          >
            <span class="size-4 text-n-slate-11" :class="[trigger.icon]" />
          </span>
          <span class="text-sm font-medium text-n-slate-12">
            {{ t(`CONVERSATION_RULES.TRIGGERS.${trigger.key}`) }}
          </span>
        </div>
        <p class="text-xs text-n-slate-11 leading-snug pl-10">
          {{ t(`CONVERSATION_RULES.TRIGGERS.${trigger.key}_HELP`) }}
        </p>
      </button>
    </div>
  </div>
</template>
