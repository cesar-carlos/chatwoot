<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import {
  MAX_FORWARD_DESTINATIONS,
  recentConversationsForInbox,
  forwardMessagesToDestinations,
  filterContactsReachableOnInbox,
  isSameDestination,
  getForwardableAttachments,
  isForwardSearchEligibleContact,
  conversationIdForContactInInbox,
  describeForwardError,
} from 'customDashboard/composables/useMessageForward';

const props = defineProps({
  message: {
    type: Object,
    default: null,
  },
  messages: {
    type: Array,
    default: () => [],
  },
  inboxId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['done', 'close']);

const { t } = useI18n();
const dialogRef = ref(null);
const searchQuery = ref('');
const searchResults = ref([]);
const selected = ref([]);
const caption = ref('');
const isSearching = ref(false);
const isForwarding = ref(false);
const searchContacts = createContactSearcher();
const allConversations = useMapGetter('getAllConversations');
const currentUser = useMapGetter('getCurrentUser');
const currentAccountId = useMapGetter('getCurrentAccountId');
const sendProgress = ref(null);
const isRetryState = ref(false);

const sourceMessages = computed(() => {
  if (Array.isArray(props.messages) && props.messages.length) {
    return props.messages;
  }
  return props.message ? [props.message] : [];
});

const primaryMessage = computed(() => sourceMessages.value[0] || null);
const isBulkForward = computed(() => sourceMessages.value.length > 1);

const snippetForMessage = message => {
  const content = (message?.content || '').trim();
  if (content) {
    return content.length > 120 ? `${content.slice(0, 120)}…` : content;
  }
  const count = getForwardableAttachments(message).length;
  if (count) {
    return t('CONVERSATION.FORWARD.ATTACHMENT_PREVIEW', { count });
  }
  return '';
};

const hasForwardableAttachments = computed(
  () => getForwardableAttachments(primaryMessage.value).length > 0
);

const previewText = computed(() => snippetForMessage(primaryMessage.value));

const dialogTitle = computed(() =>
  isBulkForward.value
    ? t('CONVERSATION.FORWARD.TITLE_MULTI', {
        count: sourceMessages.value.length,
      })
    : t('CONVERSATION.FORWARD.TITLE')
);

const dialogDescription = computed(() =>
  isBulkForward.value
    ? t('CONVERSATION.FORWARD.DESCRIPTION_MULTI')
    : t('CONVERSATION.FORWARD.DESCRIPTION')
);

const recentOptions = computed(() =>
  recentConversationsForInbox(
    allConversations.value || [],
    props.inboxId,
    primaryMessage.value?.conversation_id ||
      primaryMessage.value?.conversationId
  )
);

const canConfirm = computed(
  () => selected.value.length > 0 && !isForwarding.value
);

const confirmLabel = computed(() =>
  isRetryState.value
    ? t('CONVERSATION.FORWARD.RETRY')
    : t('CONVERSATION.FORWARD.CONFIRM')
);

const progressLabel = computed(() => {
  if (!sendProgress.value) return '';
  return t('CONVERSATION.FORWARD.SENDING_PROGRESS', sendProgress.value);
});

const forwardErrorText = entry => {
  if (entry?.code) {
    return t(`CONVERSATION.FORWARD.ERRORS.${entry.code}`, {
      status: entry.details?.status,
    });
  }
  return entry?.message || '';
};

const isSelected = destination =>
  selected.value.some(item => isSameDestination(item, destination));

const toggleDestination = destination => {
  const existing = selected.value.find(item =>
    isSameDestination(item, destination)
  );
  if (existing) {
    // Same row key → deselect; different representation of same chat → warn
    if (existing.key === destination.key) {
      selected.value = selected.value.filter(
        item => !isSameDestination(item, destination)
      );
      return;
    }
    useAlert(t('CONVERSATION.FORWARD.DUPLICATE_DESTINATION'));
    return;
  }
  if (selected.value.length >= MAX_FORWARD_DESTINATIONS) {
    useAlert(
      t('CONVERSATION.FORWARD.MAX_DESTINATIONS', {
        count: MAX_FORWARD_DESTINATIONS,
      })
    );
    return;
  }
  selected.value = [...selected.value, destination];
};

const removeDestination = key => {
  selected.value = selected.value.filter(item => item.key !== key);
};

const mapContactOption = contact => {
  const conversationId = conversationIdForContactInInbox(
    allConversations.value || [],
    contact.id,
    props.inboxId
  );
  return {
    key: conversationId
      ? `conversation:${conversationId}`
      : `contact:${contact.id}`,
    contactId: contact.id,
    conversationId,
    label: contact.name,
    phoneNumber: contact.phoneNumber || contact.phone_number || '',
    thumbnail: contact.thumbnail || '',
    kind: conversationId ? 'conversation' : 'contact',
  };
};

const onSearch = debounce(async query => {
  isSearching.value = true;
  try {
    const results = await searchContacts(query, { reachableOnly: false });
    if (results === null) return;

    const eligible = (results || []).filter(isForwardSearchEligibleContact);
    const reachable = await filterContactsReachableOnInbox(
      eligible,
      props.inboxId,
      { conversations: allConversations.value || [] }
    );
    searchResults.value = reachable.map(mapContactOption);
  } catch {
    useAlert(t('CONVERSATION.FORWARD.SEARCH_ERROR'));
  } finally {
    isSearching.value = false;
  }
}, 300);

watch(searchQuery, value => {
  onSearch(value);
});

const resetState = () => {
  searchQuery.value = '';
  searchResults.value = [];
  selected.value = [];
  caption.value = primaryMessage.value?.content || '';
  isForwarding.value = false;
  sendProgress.value = null;
  isRetryState.value = false;
};

const open = () => {
  resetState();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
  resetState();
  emit('close');
};

const handleConfirm = async () => {
  if (!canConfirm.value || !sourceMessages.value.length) return;

  isForwarding.value = true;
  sendProgress.value = null;
  try {
    const results = await forwardMessagesToDestinations({
      sourceMessages: sourceMessages.value,
      destinations: selected.value,
      inboxId: props.inboxId,
      assigneeId: currentUser.value?.id,
      contentOverride: isBulkForward.value ? undefined : caption.value,
      onProgress: progress => {
        sendProgress.value = progress;
      },
    });

    if (results.failed === 0) {
      const conversationId = results.succeededConversationIds?.[0];
      const openPath =
        results.succeeded === 1 && conversationId && currentAccountId.value
          ? frontendURL(
              conversationUrl({
                accountId: currentAccountId.value,
                id: conversationId,
              })
            )
          : null;
      useAlert(
        t('CONVERSATION.FORWARD.SUCCESS', { count: results.succeeded }),
        openPath
          ? {
              type: 'link',
              to: openPath,
              message: t('CONVERSATION.FORWARD.OPEN_CONVERSATION'),
              duration: 6000,
            }
          : null
      );
      emit('done', results);
      close();
      return;
    }

    if (results.succeeded > 0) {
      const detail = results.errors
        .map(forwardErrorText)
        .filter(Boolean)
        .slice(0, 2)
        .join('; ');
      useAlert(
        detail
          ? t('CONVERSATION.FORWARD.PARTIAL_DETAIL', {
              ok: results.succeeded,
              fail: results.failed,
              detail,
            })
          : t('CONVERSATION.FORWARD.PARTIAL', {
              ok: results.succeeded,
              fail: results.failed,
            })
      );
      selected.value = results.failedDestinations || [];
      isRetryState.value = true;
      emit('done', results);
      return;
    }

    const detail = forwardErrorText(results.errors?.[0]);
    useAlert(
      detail
        ? t('CONVERSATION.FORWARD.FAILED_DETAIL', { detail })
        : t('CONVERSATION.FORWARD.FAILED')
    );
    isRetryState.value = true;
  } catch (error) {
    const detail = forwardErrorText(describeForwardError(error));
    useAlert(
      detail
        ? t('CONVERSATION.FORWARD.FAILED_DETAIL', { detail })
        : t('CONVERSATION.FORWARD.FAILED')
    );
  } finally {
    isForwarding.value = false;
    sendProgress.value = null;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    width="md"
    overflow-y-auto
    :title="dialogTitle"
    :description="dialogDescription"
    :confirm-button-label="confirmLabel"
    :cancel-button-label="$t('CONVERSATION.FORWARD.CANCEL')"
    :disable-confirm-button="!canConfirm"
    :is-loading="isForwarding"
    @confirm="handleConfirm"
    @close="resetState"
  >
    <div class="flex flex-col gap-3">
      <p v-if="isForwarding && progressLabel" class="text-xs text-n-slate-11">
        {{ progressLabel }}
      </p>
      <div
        v-if="isBulkForward"
        class="flex max-h-40 flex-col gap-1.5 overflow-y-auto"
      >
        <div
          v-for="item in sourceMessages"
          :key="item.id"
          class="rounded-lg border border-n-strong bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-12"
        >
          <p class="line-clamp-2 whitespace-pre-wrap break-words">
            {{ snippetForMessage(item) }}
          </p>
        </div>
      </div>
      <div
        v-else
        class="rounded-lg border border-n-strong bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-12"
      >
        <div class="mb-1 flex items-center gap-1.5 text-xs text-n-slate-11">
          <Icon
            v-if="hasForwardableAttachments"
            icon="i-lucide-paperclip"
            class="size-3.5"
          />
          <span>{{ $t('CONVERSATION.FORWARD.PREVIEW_LABEL') }}</span>
        </div>
        <p class="line-clamp-3 whitespace-pre-wrap break-words">
          {{ previewText }}
        </p>
      </div>

      <div v-if="!isBulkForward" class="flex flex-col gap-1">
        <label
          class="text-xs font-medium text-n-slate-11"
          for="forward-caption"
        >
          {{ $t('CONVERSATION.FORWARD.CAPTION_LABEL') }}
        </label>
        <textarea
          id="forward-caption"
          v-model="caption"
          rows="2"
          class="w-full resize-y rounded-lg border border-n-strong bg-n-background px-3 py-2 text-sm outline-none focus:border-n-brand"
          :placeholder="$t('CONVERSATION.FORWARD.CAPTION_PLACEHOLDER')"
        />
      </div>

      <div v-if="selected.length" class="flex flex-wrap gap-1.5">
        <button
          v-for="item in selected"
          :key="item.key"
          type="button"
          class="inline-flex items-center gap-1 rounded-full border border-n-brand bg-n-alpha-2 px-2 py-0.5 text-xs"
          @click="removeDestination(item.key)"
        >
          <span>{{ item.label }}</span>
          <Icon icon="i-lucide-x" class="size-3" />
        </button>
      </div>

      <input
        v-model="searchQuery"
        type="search"
        class="w-full rounded-lg border border-n-strong bg-n-background px-3 py-2 text-sm outline-none focus:border-n-brand"
        :placeholder="$t('CONVERSATION.FORWARD.SEARCH_PLACEHOLDER')"
      />

      <div v-if="searchQuery.trim()" class="flex flex-col gap-1">
        <div class="text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION.FORWARD.SEARCH_RESULTS') }}
        </div>
        <p v-if="isSearching" class="px-1 py-2 text-xs text-n-slate-11">
          {{ $t('CONVERSATION.FORWARD.SEARCHING') }}
        </p>
        <p
          v-else-if="!searchResults.length"
          class="px-1 py-2 text-xs text-n-slate-11"
        >
          {{ $t('CONVERSATION.FORWARD.NO_RESULTS') }}
        </p>
        <button
          v-for="item in searchResults"
          :key="item.key"
          type="button"
          class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-n-alpha-2"
          :class="{ 'ring-1 ring-n-brand': isSelected(item) }"
          @click="toggleDestination(item)"
        >
          <Avatar
            :name="item.label"
            :src="item.thumbnail"
            :size="28"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <div class="truncate text-sm text-n-slate-12">{{ item.label }}</div>
            <div
              v-if="item.phoneNumber"
              class="truncate text-xs text-n-slate-11"
            >
              {{ item.phoneNumber }}
            </div>
          </div>
          <Icon
            v-if="isSelected(item)"
            icon="i-lucide-check"
            class="size-4 text-n-brand"
          />
        </button>
      </div>

      <div v-else class="flex flex-col gap-1">
        <div class="text-xs font-medium text-n-slate-11">
          {{ $t('CONVERSATION.FORWARD.RECENT') }}
        </div>
        <p
          v-if="!recentOptions.length"
          class="px-1 py-2 text-xs text-n-slate-11"
        >
          {{ $t('CONVERSATION.FORWARD.NO_RECENT') }}
        </p>
        <button
          v-for="item in recentOptions"
          :key="item.key"
          type="button"
          class="flex items-center gap-2 rounded-lg px-2 py-1.5 text-left hover:bg-n-alpha-2"
          :class="{ 'ring-1 ring-n-brand': isSelected(item) }"
          @click="toggleDestination(item)"
        >
          <Avatar
            :name="item.label"
            :src="item.thumbnail"
            :size="28"
            rounded-full
          />
          <div class="min-w-0 flex-1">
            <div class="truncate text-sm text-n-slate-12">{{ item.label }}</div>
            <div
              v-if="item.phoneNumber"
              class="truncate text-xs text-n-slate-11"
            >
              {{ item.phoneNumber }}
            </div>
          </div>
          <Icon
            v-if="isSelected(item)"
            icon="i-lucide-check"
            class="size-4 text-n-brand"
          />
        </button>
      </div>

      <p class="text-xs text-n-slate-11">
        {{
          $t('CONVERSATION.FORWARD.SELECTION_HINT', {
            count: selected.length,
            max: MAX_FORWARD_DESTINATIONS,
          })
        }}
      </p>
    </div>
  </Dialog>
</template>
