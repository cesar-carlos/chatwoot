<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { isWavoipInboxRestricted } from 'customDashboard/composables/wavoip/useWavoipNotifications';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();

const inbox = computed(() =>
  props.inboxId ? store.getters['inboxes/getInbox']?.(props.inboxId) : null
);

const isWavoipInbox = computed(
  () => inbox.value?.channel_type === INBOX_TYPES.WAVOIP
);

const deviceStatus = computed(() => {
  if (!props.inboxId) return null;
  return getWavoipDeviceStatus(props.inboxId).connectionStatus.value;
});

const isRestricted = computed(() =>
  props.inboxId ? isWavoipInboxRestricted(props.inboxId) : false
);

const bannerMessage = computed(() => {
  if (!isWavoipInbox.value) return null;
  if (isRestricted.value) {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTRICTED');
  }
  if (deviceStatus.value === 'disconnected') {
    return t('CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED');
  }
  if (deviceStatus.value === 'reconnecting') {
    return t('CONVERSATION.WAVOIP_CALL.DEVICE_RECONNECTING');
  }
  return null;
});
</script>

<template>
  <div
    v-if="bannerMessage"
    class="border-b border-n-amber-6 bg-n-amber-2 px-4 py-2 text-sm text-n-amber-12"
    role="status"
  >
    {{ bannerMessage }}
  </div>
</template>
