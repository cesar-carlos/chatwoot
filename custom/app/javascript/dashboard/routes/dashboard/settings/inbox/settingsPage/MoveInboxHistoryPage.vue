<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const POLL_MS = 5000;

const props = defineProps({
  inbox: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const selectedTargetId = ref(null);
const showConfirmModal = ref(false);
const isSubmitting = ref(false);
const migration = ref(null);
let pollTimer = null;

function isWhatsAppLike(inbox) {
  if (!inbox) return false;
  if (inbox.channel_type === INBOX_TYPES.WHATSAPP) return true;
  return (
    inbox.channel_type === INBOX_TYPES.TWILIO && inbox.medium === 'whatsapp'
  );
}

const targetOptions = computed(() =>
  (inboxes.value || [])
    .filter(item => item.id !== props.inbox.id && isWhatsAppLike(item))
    .map(item => ({
      value: item.id,
      label: item.phone_number
        ? `${item.name} (${item.phone_number})`
        : item.name,
    }))
);

const isRunning = computed(() => migration.value?.status === 'running');
const isPending = computed(() => migration.value?.status === 'pending');
const isActive = computed(() => isPending.value || isRunning.value);
const isCompleted = computed(() => migration.value?.status === 'completed');
const isFailed = computed(() => migration.value?.status === 'failed');
const stats = computed(() => migration.value?.stats || {});

const selectedTargetLabel = computed(() => {
  const option = targetOptions.value.find(
    item => item.value === selectedTargetId.value
  );
  return option?.label || '';
});

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

async function refreshStatus() {
  if (!props.inbox?.id) return;
  try {
    const data = await store.dispatch(
      'inboxes/fetchMoveHistoryStatus',
      props.inbox.id
    );
    migration.value = data?.id ? data : null;
  } catch {
    // Status poll failures should not block the page.
  }
}

function startPollingIfNeeded() {
  stopPolling();
  if (!isActive.value) return;

  pollTimer = setInterval(() => {
    refreshStatus();
  }, POLL_MS);
}

watch(isActive, active => {
  if (active) startPollingIfNeeded();
  else stopPolling();
});

onMounted(async () => {
  await refreshStatus();
  startPollingIfNeeded();
});

onBeforeUnmount(stopPolling);

function openConfirm() {
  if (!selectedTargetId.value) {
    useAlert(t('INBOX_MGMT.MOVE_HISTORY.ERRORS.TARGET_REQUIRED'));
    return;
  }
  showConfirmModal.value = true;
}

function closeConfirm() {
  showConfirmModal.value = false;
}

async function confirmMove() {
  isSubmitting.value = true;
  try {
    const data = await store.dispatch('inboxes/moveInboxHistory', {
      inboxId: props.inbox.id,
      targetInboxId: selectedTargetId.value,
    });
    migration.value = data;
    showConfirmModal.value = false;
    useAlert(t('INBOX_MGMT.MOVE_HISTORY.API.STARTED'));
    startPollingIfNeeded();
  } catch (error) {
    const message =
      error?.response?.data?.error ||
      t('INBOX_MGMT.MOVE_HISTORY.API.ERROR_MESSAGE');
    useAlert(message);
  } finally {
    isSubmitting.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-6 max-w-2xl">
    <div class="flex flex-col gap-2">
      <h3 class="text-heading-3 text-n-slate-12">
        {{ $t('INBOX_MGMT.MOVE_HISTORY.TITLE') }}
      </h3>
      <p class="text-n-slate-11 text-sm">
        {{ $t('INBOX_MGMT.MOVE_HISTORY.DESCRIPTION') }}
      </p>
    </div>

    <SettingsFieldSection :label="$t('INBOX_MGMT.MOVE_HISTORY.TARGET_LABEL')">
      <SelectInput
        v-model="selectedTargetId"
        :placeholder="$t('INBOX_MGMT.MOVE_HISTORY.TARGET_PLACEHOLDER')"
        :options="targetOptions"
        :disabled="isActive"
      />
    </SettingsFieldSection>

    <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 text-sm text-n-slate-11">
      <p>{{ $t('INBOX_MGMT.MOVE_HISTORY.WARNING') }}</p>
    </div>

    <div class="flex justify-end">
      <NextButton
        :label="$t('INBOX_MGMT.MOVE_HISTORY.START_BUTTON')"
        :disabled="isActive || !selectedTargetId"
        :is-loading="isSubmitting"
        @click="openConfirm"
      />
    </div>

    <div
      v-if="migration"
      class="rounded-xl border border-n-weak bg-n-surface-1 p-4 flex flex-col gap-2"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-heading-4 text-n-slate-12">
          {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.TITLE') }}
        </span>
        <span class="text-sm text-n-slate-11 capitalize">
          {{ migration.status }}
        </span>
      </div>

      <div
        v-if="isActive || isCompleted || isFailed"
        class="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm"
      >
        <div>
          <div class="text-n-slate-10">
            {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.MOVED') }}
          </div>
          <div class="text-n-slate-12 font-medium">{{ stats.moved || 0 }}</div>
        </div>
        <div>
          <div class="text-n-slate-10">
            {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.MERGED') }}
          </div>
          <div class="text-n-slate-12 font-medium">{{ stats.merged || 0 }}</div>
        </div>
        <div>
          <div class="text-n-slate-10">
            {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.SKIPPED') }}
          </div>
          <div class="text-n-slate-12 font-medium">
            {{ stats.skipped || 0 }}
          </div>
        </div>
        <div>
          <div class="text-n-slate-10">
            {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.FAILED') }}
          </div>
          <div class="text-n-slate-12 font-medium">{{ stats.failed || 0 }}</div>
        </div>
      </div>

      <p v-if="isFailed && migration.error_message" class="text-sm text-n-ruby-11">
        {{ migration.error_message }}
      </p>
    </div>

    <woot-confirm-delete-modal
      v-if="showConfirmModal"
      v-model:show="showConfirmModal"
      :title="$t('INBOX_MGMT.MOVE_HISTORY.CONFIRM.TITLE')"
      :message="
        $t('INBOX_MGMT.MOVE_HISTORY.CONFIRM.MESSAGE', {
          source: inbox.name,
          target: selectedTargetLabel,
        })
      "
      :confirm-text="$t('INBOX_MGMT.MOVE_HISTORY.CONFIRM.YES')"
      :reject-text="$t('INBOX_MGMT.MOVE_HISTORY.CONFIRM.NO')"
      :confirm-value="inbox.name"
      :confirm-place-holder-text="
        $t('INBOX_MGMT.MOVE_HISTORY.CONFIRM.PLACEHOLDER', {
          inboxName: inbox.name,
        })
      "
      @on-confirm="confirmMove"
      @on-close="closeConfirm"
    />
  </div>
</template>
