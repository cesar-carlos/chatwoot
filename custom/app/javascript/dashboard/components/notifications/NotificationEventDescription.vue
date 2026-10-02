<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  description: { type: String, default: '' },
});
const { t } = useI18n();
</script>

<template>
  <span
    v-show="description"
    class="block mt-1 text-xs font-normal tracking-normal text-n-slate-11"
  >
    {{ description ? t(description) : '' }}
  </span>
</template>
