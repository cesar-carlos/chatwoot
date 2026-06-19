<script setup>
defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-2"
  >
    <div class="flex flex-col gap-0.5">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ title }}
      </h3>
      <p v-if="description" class="text-sm text-n-slate-11">
        {{ description }}
      </p>
    </div>
    <slot />
  </section>
</template>
