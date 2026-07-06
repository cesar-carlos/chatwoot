<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useWavoipCallSession } from 'customDashboard/composables/wavoip/useWavoipCallSession';
import { getWavoipSdkSyncKey } from 'customDashboard/composables/wavoip/useWavoipConnection';
import { registerWavoipCallSession } from 'customDashboard/lib/voice/voiceSessionRegistry';
import { requestWavoipNotificationPermission } from 'customDashboard/composables/wavoip/useWavoipNotifications';
import { isIosSafariWithoutPwa } from 'customDashboard/lib/wavoip/wavoipNotificationEnvironment';

const store = useStore();
const { t } = useI18n();
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const wavoipSdkSyncKey = computed(() => getWavoipSdkSyncKey(store));
const wavoipSession = useWavoipCallSession();
const { syncWithAvailability, cleanupSession } = wavoipSession;
const showIosHint = ref(isIosSafariWithoutPwa());

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
  <div>
    <div
      v-if="showIosHint && currentUserAvailability === 'online'"
      class="fixed bottom-20 left-4 right-4 z-40 mx-auto max-w-lg rounded-lg border border-n-amber-6 bg-n-amber-2 px-4 py-3 text-sm text-n-amber-12 shadow-md sm:left-auto"
      role="status"
    >
      <div class="flex items-start justify-between gap-3">
        <p>
          {{ t('PROFILE_SETTINGS.FORM.NOTIFICATIONS.WAVOIP_IOS_PWA_HINT') }}
        </p>
        <button
          type="button"
          class="shrink-0 text-n-amber-11 hover:text-n-amber-12"
          :aria-label="t('CONVERSATION.HEADER.CLOSE')"
          @click="showIosHint = false"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>
    </div>
  </div>
</template>
