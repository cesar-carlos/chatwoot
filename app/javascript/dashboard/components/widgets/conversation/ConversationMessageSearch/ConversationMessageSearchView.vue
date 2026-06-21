<script setup>
import {
  computed,
  nextTick,
  onMounted,
  onUnmounted,
  ref,
  toRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useTrack } from 'dashboard/composables';
import { MESSAGE_SEARCH_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';

import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ConversationMessageSearchResultItem from './ConversationMessageSearchResultItem.vue';
import { useConversationMessageSearch } from 'dashboard/composables/fork/useConversationMessageSearch';
import { useScrollToConversationMessage } from 'dashboard/composables/fork/useScrollToConversationMessage';

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
  onClose: {
    type: Function,
    default: null,
  },
});

const { t } = useI18n();

const searchInputRef = ref(null);
const panelRef = ref(null);
const resultsContainerRef = ref(null);
const loadMoreSentinelRef = ref(null);
const activeResultIndex = ref(-1);

const conversationIdRef = toRef(props, 'conversationId');

const {
  query,
  results,
  hasMore,
  isSearching,
  errorMessage,
  fromFilter,
  hitMaxResults,
  recentSearches,
  loadMore,
  restoreLastQuery,
  applyRecentSearch,
  close: closeSearch,
} = useConversationMessageSearch(conversationIdRef);

const FILTER_OPTIONS = [
  { value: '', label: () => t('CONVERSATION.MESSAGE_SEARCH.FILTER_ALL') },
  {
    value: 'contact',
    label: () => t('CONVERSATION.MESSAGE_SEARCH.FILTER_CONTACT'),
  },
  {
    value: 'agent',
    label: () => t('CONVERSATION.MESSAGE_SEARCH.FILTER_AGENT'),
  },
  {
    value: 'private',
    label: () => t('CONVERSATION.MESSAGE_SEARCH.FILTER_PRIVATE'),
  },
];

const close = () => {
  closeSearch();
  activeResultIndex.value = -1;
  props.onClose?.();
};

const { scrollToMessage, isLocating } = useScrollToConversationMessage({
  conversationId: conversationIdRef,
  onClose: close,
});

const trimmedQuery = computed(() => query.value.trim());
const showHint = computed(() => trimmedQuery.value.length < 2);
const showInitialLoading = computed(
  () => isSearching.value && !results.value.length
);
const showResults = computed(() => results.value.length > 0);
const showEmpty = computed(
  () =>
    !isSearching.value &&
    trimmedQuery.value.length >= 2 &&
    !results.value.length &&
    !errorMessage.value
);
const showError = computed(() => Boolean(errorMessage.value));
const resultsCountLabel = computed(() =>
  t('CONVERSATION.MESSAGE_SEARCH.RESULTS_COUNT', {
    count: results.value.length,
  })
);

const handleSelect = async message => {
  useTrack(MESSAGE_SEARCH_EVENTS.RESULT_CLICKED, { messageId: message.id });
  await scrollToMessage(message);
};

const focusSearchInput = () => {
  nextTick(() => {
    searchInputRef.value?.$el?.querySelector('input')?.focus();
  });
};

const prepareOpen = () => {
  closeSearch();
  restoreLastQuery();
  focusSearchInput();
};

const selectActiveResult = () => {
  const message = results.value[activeResultIndex.value];
  if (message) handleSelect(message);
};

const isSearchInputFocused = () => {
  const input = searchInputRef.value?.$el?.querySelector('input');
  return input && document.activeElement === input;
};

const isInsideSearchPanel = () => {
  const activeElement = document.activeElement;
  return panelRef.value?.contains(activeElement);
};

const onResultsKeydown = event => {
  if (!isInsideSearchPanel()) return;

  if (event.key === 'Escape') {
    event.preventDefault();
    close();
    return;
  }

  if (!showResults.value || isLocating.value) return;

  if (isSearchInputFocused() && event.key === 'ArrowDown') {
    event.preventDefault();
    activeResultIndex.value = 0;
    return;
  }

  if (isSearchInputFocused() && event.key === 'ArrowUp') {
    return;
  }

  if (event.key === 'ArrowDown') {
    event.preventDefault();
    activeResultIndex.value = Math.min(
      activeResultIndex.value + 1,
      results.value.length - 1
    );
  } else if (event.key === 'ArrowUp') {
    event.preventDefault();
    activeResultIndex.value = Math.max(activeResultIndex.value - 1, 0);
  } else if (event.key === 'Enter') {
    if (results.value.length === 1) {
      event.preventDefault();
      handleSelect(results.value[0]);
    } else if (activeResultIndex.value >= 0) {
      event.preventDefault();
      selectActiveResult();
    }
  }
};

let loadMoreObserver = null;

const setupInfiniteScroll = () => {
  loadMoreObserver?.disconnect();
  if (!loadMoreSentinelRef.value || !resultsContainerRef.value) return;

  loadMoreObserver = new IntersectionObserver(
    entries => {
      if (entries.some(entry => entry.isIntersecting)) {
        loadMore();
      }
    },
    { root: resultsContainerRef.value, rootMargin: '120px' }
  );
  loadMoreObserver.observe(loadMoreSentinelRef.value);
};

watch([showResults, hasMore], () => {
  nextTick(() => setupInfiniteScroll());
});

watch(activeResultIndex, () => {
  nextTick(() => {
    const activeElement = resultsContainerRef.value?.querySelector(
      '[aria-selected="true"]'
    );
    activeElement?.scrollIntoView({ block: 'nearest' });
  });
});

watch(results, () => {
  if (activeResultIndex.value >= results.value.length) {
    activeResultIndex.value = results.value.length ? 0 : -1;
  }
});

onMounted(() => {
  window.addEventListener('keydown', onResultsKeydown);
});

onUnmounted(() => {
  window.removeEventListener('keydown', onResultsKeydown);
  loadMoreObserver?.disconnect();
});

defineExpose({ prepareOpen, close, focusSearchInput });
</script>

<template>
  <div
    ref="panelRef"
    data-message-search-panel
    class="flex flex-col gap-4 w-full"
  >
    <label class="sr-only" for="conversation-message-search-input">
      {{ t('CONVERSATION.MESSAGE_SEARCH.PLACEHOLDER') }}
    </label>
    <Input
      id="conversation-message-search-input"
      ref="searchInputRef"
      v-model="query"
      :placeholder="t('CONVERSATION.MESSAGE_SEARCH.PLACEHOLDER')"
      :disabled="isLocating"
      autofocus
    />

    <p v-if="showHint" class="text-sm text-n-slate-11">
      {{ t('CONVERSATION.MESSAGE_SEARCH.HINT') }}
      <span class="block mt-1">{{
        t('CONVERSATION.MESSAGE_SEARCH.HINT_TRANSCRIPTION')
      }}</span>
    </p>

    <div
      class="flex flex-wrap gap-2"
      role="group"
      :aria-label="t('CONVERSATION.MESSAGE_SEARCH.FILTER_ALL')"
    >
      <button
        v-for="option in FILTER_OPTIONS"
        :key="option.value"
        type="button"
        class="px-3 py-1 text-xs rounded-full border transition-colors"
        :class="
          fromFilter === option.value
            ? 'border-n-brand bg-n-brand/10 text-n-brand'
            : 'border-n-weak text-n-slate-11 hover:bg-n-slate-2'
        "
        :aria-pressed="fromFilter === option.value"
        @click="fromFilter = option.value"
      >
        {{ option.label() }}
      </button>
    </div>

    <div
      v-if="recentSearches.length && showHint"
      class="flex flex-wrap gap-2 items-center"
    >
      <span class="text-xs text-n-slate-11">{{
        t('CONVERSATION.MESSAGE_SEARCH.RECENT')
      }}</span>
      <button
        v-for="recent in recentSearches"
        :key="recent"
        type="button"
        class="px-2 py-0.5 text-xs rounded-md bg-n-slate-2 text-n-slate-12 hover:bg-n-slate-3"
        @click="applyRecentSearch(recent)"
      >
        {{ recent }}
      </button>
    </div>

    <woot-loading-state
      v-if="showInitialLoading"
      :message="t('CONVERSATION.MESSAGE_SEARCH.SEARCHING')"
    />

    <div
      v-if="showError"
      class="flex items-start gap-2 px-4 py-3 rounded-xl bg-n-ruby-3 text-n-ruby-11"
    >
      <Icon icon="i-lucide-circle-alert" class="size-4 flex-shrink-0 mt-0.5" />
      <p class="text-sm">
        {{ errorMessage }}
      </p>
    </div>

    <div
      v-if="showEmpty"
      class="flex items-start justify-center gap-2 px-4 py-6 rounded-xl bg-n-slate-2 dark:bg-n-solid-1"
    >
      <Icon
        icon="i-lucide-info"
        class="text-n-slate-11 size-4 flex-shrink-0 mt-0.5"
      />
      <p class="text-sm text-center text-n-slate-11">
        {{ t('CONVERSATION.MESSAGE_SEARCH.EMPTY', { query: trimmedQuery }) }}
      </p>
    </div>

    <div v-if="showResults" class="flex flex-col gap-2">
      <p class="text-sm text-n-slate-11">{{ resultsCountLabel }}</p>

      <div
        ref="resultsContainerRef"
        class="flex flex-col gap-2 max-h-[min(50vh,24rem)] overflow-y-auto"
        role="listbox"
        :aria-label="t('CONVERSATION.MESSAGE_SEARCH.PANEL_TITLE')"
      >
        <ConversationMessageSearchResultItem
          v-for="(message, index) in results"
          :id="`conversation-message-search-result-${message.id}`"
          :key="message.id"
          :message="message"
          :search-query="query"
          :disabled="isLocating"
          :active="index === activeResultIndex"
          @select="handleSelect"
        />
        <div
          v-if="hasMore"
          ref="loadMoreSentinelRef"
          class="flex justify-center py-2"
        >
          <span v-if="isSearching" class="text-xs text-n-slate-11">{{
            t('CONVERSATION.MESSAGE_SEARCH.SEARCHING')
          }}</span>
        </div>
      </div>

      <p v-if="hitMaxResults" class="text-xs text-center text-n-slate-11">
        {{ t('CONVERSATION.MESSAGE_SEARCH.MAX_RESULTS') }}
      </p>
    </div>

    <div
      v-if="isLocating"
      class="flex items-center gap-2 text-sm text-n-slate-11"
    >
      <Icon icon="i-lucide-loader-circle" class="size-4 animate-spin" />
      {{ t('CONVERSATION.MESSAGE_SEARCH.LOCATING') }}
    </div>
  </div>
</template>
