import { ref, watch, onUnmounted, unref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTrack } from 'dashboard/composables';
import { MESSAGE_SEARCH_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import ConversationMessageSearchAPI from 'dashboard/api/conversationMessageSearch';
import { resolveConversationMessageSearchError } from 'dashboard/composables/fork/resolveConversationMessageSearchError';

const DEBOUNCE_MS = 500;
const MIN_QUERY_LENGTH = 2;
const STORAGE_PREFIX = 'conversation_message_search';
const MAX_RECENT_SEARCHES = 5;

const isAbortedRequest = error =>
  error?.name === 'AbortError' ||
  error?.name === 'CanceledError' ||
  error?.code === 'ERR_CANCELED';

const dedupeById = messages => {
  const seen = new Set();
  return messages.filter(message => {
    if (seen.has(message.id)) return false;
    seen.add(message.id);
    return true;
  });
};

const storageKey = conversationId => `${STORAGE_PREFIX}:${conversationId}`;

const readStorage = conversationId => {
  try {
    const raw = sessionStorage.getItem(storageKey(conversationId));
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
};

const writeStorage = (conversationId, data) => {
  try {
    sessionStorage.setItem(storageKey(conversationId), JSON.stringify(data));
  } catch {
    // sessionStorage may be unavailable
  }
};

const pushRecentSearch = (conversationId, query) => {
  const trimmed = query.trim();
  if (trimmed.length < MIN_QUERY_LENGTH) return;

  const stored = readStorage(conversationId);
  const recent = [
    trimmed,
    ...(stored.recentSearches || []).filter(q => q !== trimmed),
  ].slice(0, MAX_RECENT_SEARCHES);
  writeStorage(conversationId, { ...stored, recentSearches: recent });
};

export const useConversationMessageSearch = conversationIdSource => {
  const { t } = useI18n();
  const query = ref('');
  const results = ref([]);
  const currentPage = ref(1);
  const hasMore = ref(false);
  const isSearching = ref(false);
  const error = ref(null);
  const errorMessage = ref('');
  const isRateLimited = ref(false);
  const fromFilter = ref('');
  const hitMaxResults = ref(false);
  const recentSearches = ref([]);
  const searchEngine = ref(null);

  let abortController = null;
  let debounceTimer = null;
  let requestId = 0;

  const cancelPending = () => {
    if (debounceTimer) {
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    abortController?.abort();
    abortController = null;
  };

  const resetResults = () => {
    results.value = [];
    currentPage.value = 1;
    hasMore.value = false;
    hitMaxResults.value = false;
    error.value = null;
    errorMessage.value = '';
    isRateLimited.value = false;
  };

  const executeSearch = async (page, { append = false } = {}) => {
    const conversationId = unref(conversationIdSource);
    const trimmedQuery = query.value.trim();

    if (trimmedQuery.length < MIN_QUERY_LENGTH || !conversationId) {
      resetResults();
      isSearching.value = false;
      return;
    }

    abortController?.abort();
    abortController = new AbortController();
    const { signal } = abortController;
    requestId += 1;
    const currentRequestId = requestId;

    isSearching.value = true;
    if (!append) {
      error.value = null;
      errorMessage.value = '';
    }

    try {
      const { data } = await ConversationMessageSearchAPI.search({
        conversationId,
        query: trimmedQuery,
        page,
        from: fromFilter.value || undefined,
        signal,
      });

      if (currentRequestId !== requestId) return;

      const payload = data.payload || [];
      const meta = data.meta || {};

      if (append) {
        results.value = dedupeById([...results.value, ...payload]);
      } else {
        results.value = payload;
        pushRecentSearch(conversationId, trimmedQuery);
        writeStorage(conversationId, {
          ...readStorage(conversationId),
          lastQuery: trimmedQuery,
          lastFrom: fromFilter.value,
        });
      }

      currentPage.value = meta.current_page || page;
      hasMore.value = Boolean(meta.has_more);
      hitMaxResults.value =
        Boolean(meta.max_results) && results.value.length >= meta.max_results;
      searchEngine.value = meta.search_engine || null;
      error.value = null;
      errorMessage.value = '';
      isRateLimited.value = false;

      if (!append) {
        useTrack(MESSAGE_SEARCH_EVENTS.SEARCHED, {
          resultCount: payload.length,
          searchEngine: searchEngine.value,
        });
      }
    } catch (err) {
      if (isAbortedRequest(err) || currentRequestId !== requestId) return;

      error.value = err;
      isRateLimited.value = err?.response?.status === 429;
      errorMessage.value = resolveConversationMessageSearchError(err, t);
      if (!append) {
        results.value = [];
      }
    } finally {
      if (currentRequestId === requestId) {
        isSearching.value = false;
      }
    }
  };

  const scheduleSearch = () => {
    cancelPending();

    const trimmedQuery = query.value.trim();
    if (trimmedQuery.length < MIN_QUERY_LENGTH) {
      resetResults();
      isSearching.value = false;
      return;
    }

    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      currentPage.value = 1;
      executeSearch(1);
    }, DEBOUNCE_MS);
  };

  watch(query, scheduleSearch);
  watch(fromFilter, () => {
    if (query.value.trim().length >= MIN_QUERY_LENGTH) {
      scheduleSearch();
    }
  });

  watch(
    () => unref(conversationIdSource),
    conversationId => {
      cancelPending();
      resetResults();
      isSearching.value = false;
      query.value = '';
      fromFilter.value = '';

      if (!conversationId) return;

      const stored = readStorage(conversationId);
      recentSearches.value = stored.recentSearches || [];
    },
    { immediate: true }
  );

  const loadMore = () => {
    if (!hasMore.value || isSearching.value || hitMaxResults.value) return;
    executeSearch(currentPage.value + 1, { append: true });
  };

  const restoreLastQuery = () => {
    const conversationId = unref(conversationIdSource);
    if (!conversationId) return;

    const stored = readStorage(conversationId);
    if (stored.lastQuery) {
      query.value = stored.lastQuery;
      fromFilter.value = stored.lastFrom || '';
    }
    recentSearches.value = stored.recentSearches || [];
  };

  const applyRecentSearch = recentQuery => {
    query.value = recentQuery;
  };

  const close = () => {
    cancelPending();
    query.value = '';
    fromFilter.value = '';
    resetResults();
    isSearching.value = false;
  };

  onUnmounted(cancelPending);

  return {
    query,
    results,
    currentPage,
    hasMore,
    isSearching,
    error,
    errorMessage,
    isRateLimited,
    fromFilter,
    hitMaxResults,
    recentSearches,
    searchEngine,
    loadMore,
    restoreLastQuery,
    applyRecentSearch,
    close,
  };
};
