<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import {
  MAX_FORWARD_DESTINATIONS,
  recentConversationsForInbox,
  forwardMessageToDestinations,
} from 'customDashboard/composables/useMessageForward';

const props = defineProps({
  message: {
    type: Object,
    default: null,
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
const isSearching = ref(false);
const isForwarding = ref(false);
const searchContacts = createContactSearcher();
const allConversations = useMapGetter('getAllConversations');
const currentUser = useMapGetter('getCurrentUser');

const previewText = computed(() => {
  const content = props.message?.content || '';
  if (content) {
    return content.length > 120 ? `${content.slice(0, 120)}…` : content;
  }
  const attachments = props.message?.attachments || [];
  if (attachments.length) {
    return t('CONVERSATION.FORWARD.ATTACHMENT_PREVIEW', {
      count: attachments.length,
    });
  }
  return '';
});

const hasAttachments = computed(
  () => (props.message?.attachments || []).length > 0
);

const recentOptions = computed(() =>
  recentConversationsForInbox(
    allConversations.value || [],
    props.inboxId,
    props.message?.conversation_id || props.message?.conversationId
  )
);

const selectedKeys = computed(() => selected.value.map(item => item.key));

const canConfirm = computed(
  () => selected.value.length > 0 && !isForwarding.value
);

const isSelected = key => selectedKeys.value.includes(key);

const toggleDestination = destination => {
  const index = selected.value.findIndex(item => item.key === destination.key);
  if (index >= 0) {
    selected.value = selected.value.filter(
      item => item.key !== destination.key
    );
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

const mapContactOption = contact => ({
  key: `contact:${contact.id}`,
  contactId: contact.id,
  conversationId: null,
  label: contact.name,
  phoneNumber: contact.phoneNumber || contact.phone_number || '',
  thumbnail: contact.thumbnail || '',
  kind: 'contact',
});

const onSearch = debounce(async query => {
  isSearching.value = true;
  try {
    const results = await searchContacts(query);
    if (results === null) return;
    searchResults.value = (results || [])
      .filter(contact => contact.phoneNumber || contact.phone_number)
      .map(mapContactOption);
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
  isForwarding.value = false;
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
  if (!canConfirm.value || !props.message) return;

  isForwarding.value = true;
  try {
    const results = await forwardMessageToDestinations({
      sourceMessage: props.message,
      destinations: selected.value,
      inboxId: props.inboxId,
      assigneeId: currentUser.value?.id,
    });

    if (results.failed === 0) {
      useAlert(
        t('CONVERSATION.FORWARD.SUCCESS', { count: results.succeeded })
      );
      emit('done', results);
      close();
      return;
    }

    if (results.succeeded > 0) {
      useAlert(
        t('CONVERSATION.FORWARD.PARTIAL', {
          ok: results.succeeded,
          fail: results.failed,
        })
      );
      emit('done', results);
      close();
      return;
    }

    useAlert(t('CONVERSATION.FORWARD.FAILED'));
  } catch {
    useAlert(t('CONVERSATION.FORWARD.FAILED'));
  } finally {
    isForwarding.value = false;
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
    :title="$t('CONVERSATION.FORWARD.TITLE')"
    :description="$t('CONVERSATION.FORWARD.DESCRIPTION')"
    :confirm-button-label="$t('CONVERSATION.FORWARD.CONFIRM')"
    :cancel-button-label="$t('CONVERSATION.FORWARD.CANCEL')"
    :disable-confirm-button="!canConfirm"
    :is-loading="isForwarding"
    @confirm="handleConfirm"
    @close="resetState"
  >
    <div class="flex flex-col gap-3">
      <div
        class="rounded-lg border border-n-strong bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-12"
      >
        <div class="mb-1 flex items-center gap-1.5 text-xs text-n-slate-11">
          <Icon
            v-if="hasAttachments"
            icon="i-lucide-paperclip"
            class="size-3.5"
          />
          <span>{{ $t('CONVERSATION.FORWARD.PREVIEW_LABEL') }}</span>
        </div>
        <p class="line-clamp-3 whitespace-pre-wrap break-words">
          {{ previewText }}
        </p>
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
        <p
          v-if="isSearching"
          class="px-1 py-2 text-xs text-n-slate-11"
        >
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
          :class="{ 'ring-1 ring-n-brand': isSelected(item.key) }"
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
            <div v-if="item.phoneNumber" class="truncate text-xs text-n-slate-11">
              {{ item.phoneNumber }}
            </div>
          </div>
          <Icon
            v-if="isSelected(item.key)"
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
          :class="{ 'ring-1 ring-n-brand': isSelected(item.key) }"
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
            <div v-if="item.phoneNumber" class="truncate text-xs text-n-slate-11">
              {{ item.phoneNumber }}
            </div>
          </div>
          <Icon
            v-if="isSelected(item.key)"
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
