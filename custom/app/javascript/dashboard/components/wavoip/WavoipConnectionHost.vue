<script setup>
import { watch, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useWavoipCallSession } from 'customDashboard/composables/wavoip/useWavoipCallSession';
import { registerWavoipCallSession } from 'customDashboard/lib/voice/voiceSessionRegistry';
import { requestWavoipNotificationPermission } from 'customDashboard/composables/wavoip/useWavoipNotifications';

const store = useStore();
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const wavoipSession = useWavoipCallSession();
const { syncWithAvailability, cleanupSession } = wavoipSession;

registerWavoipCallSession(wavoipSession);

watch(
  currentUserAvailability,
  async availability => {
    if (availability === 'online') {
      await requestWavoipNotificationPermission();
    }
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
  registerWavoipCallSession(null);
  cleanupSession();
});
</script>

<template>
  <span class="hidden" aria-hidden="true" />
</template>
