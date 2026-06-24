<script setup>
import { computed, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useWavoipCallSession } from 'customDashboard/composables/wavoip/useWavoipCallSession';
import { getWavoipSdkSyncKey } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { registerWavoipCallSession } from 'customDashboard/lib/voice/voiceSessionRegistry';
import { requestWavoipNotificationPermission } from 'customDashboard/composables/wavoip/useWavoipNotifications';

const store = useStore();
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const wavoipSdkSyncKey = computed(() => getWavoipSdkSyncKey(store));
const wavoipSession = useWavoipCallSession();
const { syncWithAvailability, cleanupSession } = wavoipSession;

registerWavoipCallSession(wavoipSession);

watch(
  [currentUserAvailability, wavoipSdkSyncKey],
  async ([availability]) => {
    if (availability === 'online') {
      await requestWavoipNotificationPermission();
    }
    await syncWithAvailability(availability);
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  registerWavoipCallSession(null);
  cleanupSession();
});
</script>

<template>
  <span class="hidden" aria-hidden="true" />
</template>
