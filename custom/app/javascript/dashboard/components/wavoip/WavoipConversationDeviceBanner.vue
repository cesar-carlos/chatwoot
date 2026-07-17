<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { getWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatus';
import { isWavoipInboxRestricted } from 'customDashboard/composables/wavoip/useWavoipNotifications';
import { normalizeWavoipDeviceStatus } from 'customDashboard/lib/wavoip/wavoipDeviceStatusNormalize';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();
const WAVOIP_PANEL_URL = 'https://app.wavoip.com/devices';

const inbox = computed(() =>
  props.inboxId ? store.getters['inboxes/getInbox']?.(props.inboxId) : null
);

const isWavoipInbox = computed(
  () => inbox.value?.channel_type === INBOX_TYPES.WAVOIP
);

const connectionStatus = computed(() => {
  if (!props.inboxId) return null;
  return getWavoipDeviceStatus(props.inboxId).connectionStatus.value;
});

const whatsAppStatus = computed(() => {
  if (!props.inboxId) return null;
  return normalizeWavoipDeviceStatus(
    getWavoipDeviceStatus(props.inboxId).whatsAppStatus.value ||
      inbox.value?.provider_config?.device_status
  );
});

const isRestricted = computed(() =>
  props.inboxId ? isWavoipInboxRestricted(props.inboxId) : false
);

const bannerMessage = computed(() => {
  if (!isWavoipInbox.value) return null;
  if (isRestricted.value) {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.RESTRICTED');
  }
  if (whatsAppStatus.value === 'WAITING_PAYMENT') {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.WAITING_PAYMENT_HINT');
  }
  if (whatsAppStatus.value === 'EXTERNAL_INTEGRATION_ERROR') {
    return t(
      'INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.EXTERNAL_INTEGRATION_ERROR_HINT'
    );
  }
  if (whatsAppStatus.value === 'error') {
    return t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.ERROR_HINT');
  }
  if (connectionStatus.value === 'disconnected') {
    return t('CONVERSATION.WAVOIP_CALL.DEVICE_DISCONNECTED');
  }
  if (connectionStatus.value === 'reconnecting') {
    return t('CONVERSATION.WAVOIP_CALL.DEVICE_RECONNECTING');
  }
  return null;
});

const showPanelLink = computed(
  () =>
    whatsAppStatus.value === 'WAITING_PAYMENT' ||
    whatsAppStatus.value === 'EXTERNAL_INTEGRATION_ERROR' ||
    whatsAppStatus.value === 'error'
);
</script>

<template>
  <div>
    <div
      v-if="bannerMessage"
      class="border-b border-n-amber-6 bg-n-amber-2 px-4 py-2 text-sm text-n-amber-12"
      role="status"
    >
      {{ bannerMessage }}
      <a
        v-if="showPanelLink"
        :href="WAVOIP_PANEL_URL"
        target="_blank"
        rel="noopener noreferrer"
        class="ms-2 underline"
      >
        {{ $t('INBOX_MGMT.WAVOIP_CALL.DEVICE_STATUS.OPEN_WAVOIP_PANEL') }}
      </a>
    </div>
  </div>
</template>
