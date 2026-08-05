<script setup>
import { ref, watch } from 'vue';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  collapsible: {
    type: Boolean,
    default: false,
  },
  defaultOpen: {
    type: Boolean,
    default: true,
  },
});

const isOpen = ref(props.defaultOpen);

watch(
  () => props.defaultOpen,
  value => {
    isOpen.value = value;
  }
);

const toggle = () => {
  if (!props.collapsible) return;
  isOpen.value = !isOpen.value;
};
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-2"
  >
    <button
      v-if="collapsible"
      type="button"
      class="flex items-start justify-between gap-3 w-full text-left"
      @click="toggle"
    >
      <div class="flex flex-col gap-0.5 min-w-0">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ title }}
        </h3>
        <p v-if="description" class="text-sm text-n-slate-11">
          {{ description }}
        </p>
      </div>
      <span
        class="size-4 shrink-0 text-n-slate-11 mt-0.5 transition-transform"
        :class="isOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        aria-hidden="true"
      />
    </button>
    <div v-else class="flex flex-col gap-0.5">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ title }}
      </h3>
      <p v-if="description" class="text-sm text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <div v-show="!collapsible || isOpen" class="flex flex-col gap-3">
      <slot />
    </div>
  </section>
</template>
