<script setup>
import { watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useWavoipCallSession } from 'customDashboard/composables/wavoip/useWavoipCallSession';

const store = useStore();
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const { syncWithAvailability, cleanupSession } = useWavoipCallSession();

watch(
  currentUserAvailability,
  availability => {
    syncWithAvailability(availability);
  },
  { immediate: true }
);

watch(
  () => store.getters['inboxes/getInboxes']?.length,
  () => {
    if (currentUserAvailability.value === 'online') {
      syncWithAvailability('online');
    }
  }
);

onMounted(() => {
  if (currentUserAvailability.value === 'online') {
    syncWithAvailability('online');
  }
});

onBeforeUnmount(() => {
  cleanupSession();
});
</script>

<template>
  <span class="hidden" aria-hidden="true" />
</template>
