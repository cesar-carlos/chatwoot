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
const pollError = ref(false);
let pollTimer = null;
let statusRequestId = 0;

function isWhatsAppLike(inbox) {
  if (!inbox) return false;
  if (inbox.channel_type === INBOX_TYPES.WHATSAPP) return true;
  return (
    inbox.channel_type === INBOX_TYPES.TWILIO && inbox.medium === 'whatsapp'
  );
}

function isApiInbox(inbox) {
  return inbox?.channel_type === INBOX_TYPES.API;
}

function sameMigrationFamily(source, candidate) {
  // Same-type pairs, plus cross-channel archive between WhatsApp-like and API.
  if (isWhatsAppLike(source)) {
    return isWhatsAppLike(candidate) || isApiInbox(candidate);
  }
  if (isApiInbox(source)) {
    return isApiInbox(candidate) || isWhatsAppLike(candidate);
  }
  return false;
}

function resetLocalState() {
  selectedTargetId.value = null;
  showConfirmModal.value = false;
  isSubmitting.value = false;
  migration.value = null;
  pollError.value = false;
  stopPolling();
}

const targetOptions = computed(() =>
  (inboxes.value || [])
    .filter(
      item => item.id !== props.inbox.id && sameMigrationFamily(props.inbox, item)
    )
    .map(item => ({
      value: item.id,
      label: item.phone_number
        ? `${item.name} (${item.phone_number})`
        : item.name,
    }))
);

const hasTargetOptions = computed(() => targetOptions.value.length > 0);

const isRunning = computed(() => migration.value?.status === 'running');
const isPending = computed(() => migration.value?.status === 'pending');
const isActive = computed(() => isPending.value || isRunning.value);
const isCompleted = computed(() => migration.value?.status === 'completed');
const isFailed = computed(() => migration.value?.status === 'failed');
const stats = computed(() => migration.value?.stats || {});
const failedCount = computed(() => Number(stats.value.failed || 0));
const totalCount = computed(() => Number(stats.value.total || 0));
const processedCount = computed(
  () =>
    Number(stats.value.moved || 0) +
    Number(stats.value.merged || 0) +
    Number(stats.value.skipped || 0) +
    failedCount.value
);
const hasPartialFailures = computed(
  () => isCompleted.value && failedCount.value > 0
);

const statusLabel = computed(() => {
  const status = migration.value?.status;
  if (!status) return '';
  if (hasPartialFailures.value) {
    return t('INBOX_MGMT.MOVE_HISTORY.STATUS.PARTIAL');
  }
  const key = `INBOX_MGMT.MOVE_HISTORY.STATUS.${String(status).toUpperCase()}`;
  const translated = t(key);
  return translated === key ? status : translated;
});

const destinationLabel = computed(() => {
  const targetId = migration.value?.target_inbox_id || selectedTargetId.value;
  if (!targetId) return '';
  const option = targetOptions.value.find(item => item.value === targetId);
  if (option) return option.label;
  const inbox = (inboxes.value || []).find(item => item.id === targetId);
  if (!inbox) return '';
  return inbox.phone_number
    ? `${inbox.name} (${inbox.phone_number})`
    : inbox.name;
});

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

function hydrateTargetFromMigration(data) {
  if (data?.target_inbox_id && !selectedTargetId.value) {
    selectedTargetId.value = data.target_inbox_id;
  }
}

async function refreshStatus() {
  if (!props.inbox?.id) return;
  const requestId = ++statusRequestId;
  const inboxId = props.inbox.id;
  try {
    const data = await store.dispatch(
      'inboxes/fetchMoveHistoryStatus',
      inboxId
    );
    if (requestId !== statusRequestId || props.inbox.id !== inboxId) return;
    migration.value = data?.id ? data : null;
    hydrateTargetFromMigration(migration.value);
    pollError.value = false;
  } catch {
    if (requestId !== statusRequestId || props.inbox.id !== inboxId) return;
    pollError.value = true;
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

watch(
  () => props.inbox?.id,
  async (nextId, prevId) => {
    if (!nextId || nextId === prevId) return;
    resetLocalState();
    await refreshStatus();
    startPollingIfNeeded();
  }
);

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
    hydrateTargetFromMigration(data);
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
        :disabled="isActive || !hasTargetOptions"
      />
      <p
        v-if="!hasTargetOptions"
        class="mt-2 text-sm text-n-slate-10"
      >
        {{ $t('INBOX_MGMT.MOVE_HISTORY.EMPTY_TARGETS') }}
      </p>
    </SettingsFieldSection>

    <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 text-sm text-n-slate-11">
      <p>{{ $t('INBOX_MGMT.MOVE_HISTORY.WARNING') }}</p>
    </div>

    <div class="flex justify-end">
      <NextButton
        :label="$t('INBOX_MGMT.MOVE_HISTORY.START_BUTTON')"
        :disabled="isActive || !selectedTargetId || !hasTargetOptions"
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
        <span
          class="text-sm"
          :class="
            isFailed || hasPartialFailures ? 'text-n-ruby-11' : 'text-n-slate-11'
          "
        >
          {{ statusLabel }}
        </span>
      </div>

      <p v-if="destinationLabel" class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.DESTINATION') }}:
        {{ destinationLabel }}
      </p>

      <p class="text-xs text-n-slate-10">
        {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.HINT') }}
      </p>

      <div
        v-if="isActive || isCompleted || isFailed"
        class="grid grid-cols-2 md:grid-cols-5 gap-3 text-sm"
      >
        <div>
          <div class="text-n-slate-10">
            {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.TOTAL') }}
          </div>
          <div class="text-n-slate-12 font-medium">
            {{ processedCount }} / {{ totalCount || '—' }}
          </div>
        </div>
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
          <div
            class="font-medium"
            :class="failedCount > 0 ? 'text-n-ruby-11' : 'text-n-slate-12'"
          >
            {{ failedCount }}
          </div>
        </div>
      </div>

      <p v-if="hasPartialFailures" class="text-sm text-n-ruby-11">
        {{
          $t('INBOX_MGMT.MOVE_HISTORY.STATUS.PARTIAL_HINT', {
            count: failedCount,
          })
        }}
      </p>

      <p v-if="isFailed && migration.error_message" class="text-sm text-n-ruby-11">
        {{ migration.error_message }}
      </p>

      <p v-if="pollError" class="text-sm text-n-amber-11">
        {{ $t('INBOX_MGMT.MOVE_HISTORY.STATUS.POLL_ERROR') }}
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
