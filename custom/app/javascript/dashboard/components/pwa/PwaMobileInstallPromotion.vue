<script setup>
import { computed, reactive } from 'vue';
import { usePwaInstallation } from 'customDashboard/composables/usePwaInstallation';
import { usePwaInstallPromotion } from 'customDashboard/composables/usePwaInstallPromotion';
import PwaInstallationCard from './PwaInstallationCard.vue';

const props = defineProps({
  user: { type: Object, default: () => ({}) },
  accountId: { type: [String, Number], default: null },
  ready: { type: Boolean, default: false },
});
const { status } = usePwaInstallation();
const context = reactive({
  user: computed(() => props.user),
  accountId: computed(() => props.accountId),
  ready: computed(() => props.ready),
});
const { visible, dismiss } = usePwaInstallPromotion(context, status);
</script>

<template>
  <div class="shrink-0">
    <div v-if="visible" class="p-2">
      <PwaInstallationCard promotion @dismiss="dismiss" />
    </div>
  </div>
</template>
