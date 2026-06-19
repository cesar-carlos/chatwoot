<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';

defineProps({
  label: {
    type: String,
    required: true,
  },
  help: {
    type: String,
    default: '',
  },
});

const modelValue = defineModel({ type: Boolean, default: false });
</script>

<template>
  <div
    class="flex items-start justify-between gap-4 p-3 rounded-lg border border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-0.5 min-w-0">
      <span class="text-sm text-n-slate-12">{{ label }}</span>
      <span v-if="help" class="text-xs text-n-slate-11">{{ help }}</span>
    </div>
    <Switch v-model="modelValue" class="flex-shrink-0 mt-0.5" />
  </div>
</template>
