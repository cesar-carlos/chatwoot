<script setup>
import { DURATION_PRESETS } from '../constants';

const props = defineProps({
  modelValue: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['update:modelValue']);

const applyPreset = minutes => {
  emit('update:modelValue', minutes);
};

const isActive = minutes => props.modelValue === minutes;
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <button
      v-for="preset in DURATION_PRESETS"
      :key="preset.minutes"
      type="button"
      class="px-2.5 py-1 rounded-full text-xs font-medium border transition-colors"
      :class="
        isActive(preset.minutes)
          ? 'border-n-brand bg-n-brand/10 text-n-brand'
          : 'border-n-weak text-n-slate-11 hover:border-n-slate-8'
      "
      @click="applyPreset(preset.minutes)"
    >
      {{ $t(preset.labelKey) }}
    </button>
  </div>
</template>
