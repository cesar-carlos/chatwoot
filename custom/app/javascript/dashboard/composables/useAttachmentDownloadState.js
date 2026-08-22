import { ref } from 'vue';
import store from 'dashboard/store';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

const MAX_ENTRIES = 500;
const FLASH_MS = 200;

/** Shared across components so chip / bubble / sidebar stay in sync in the same tab. */
const downloadRecords = ref({});

/** Transient ids for success micro-animation. */
const justMarkedIds = ref(new Set());

/** Avoid reloading the same account/user scope from localStorage on every call. */
let currentScopeKey = null;

const storageKeyFor = (accountId, userId) =>
  `${LOCAL_STORAGE_KEYS.ATTACHMENT_DOWNLOAD_STATE}::${accountId}::${userId}`;

const loadRecords = (accountId, userId) => {
  if (!accountId || !userId) {
    downloadRecords.value = {};
    return;
  }

  downloadRecords.value =
    LocalStorage.get(storageKeyFor(accountId, userId)) || {};
};

const pruneRecords = records => {
  const entries = Object.entries(records);
  if (entries.length <= MAX_ENTRIES) return records;

  return Object.fromEntries(
    entries
      .sort(
        (a, b) => (b[1]?.lastDownloadedAt || 0) - (a[1]?.lastDownloadedAt || 0)
      )
      .slice(0, MAX_ENTRIES)
  );
};

const persistRecords = (accountId, userId) => {
  if (!accountId || !userId) return;

  downloadRecords.value = pruneRecords(downloadRecords.value);
  LocalStorage.set(storageKeyFor(accountId, userId), downloadRecords.value);
};

const resolveScope = () => {
  const accountId = store.getters.getCurrentAccountId;
  const userId = store.getters.getCurrentUserID;
  return {
    accountId,
    userId,
    key: `${accountId ?? ''}::${userId ?? ''}`,
  };
};

const ensureLoaded = () => {
  const { accountId, userId, key } = resolveScope();
  if (currentScopeKey === key) {
    return { accountId, userId };
  }

  currentScopeKey = key;
  loadRecords(accountId, userId);
  return { accountId, userId };
};

const flashMarked = attachmentId => {
  if (attachmentId == null) return;
  const id = String(attachmentId);
  const next = new Set(justMarkedIds.value);
  next.add(id);
  justMarkedIds.value = next;

  window.setTimeout(() => {
    const updated = new Set(justMarkedIds.value);
    updated.delete(id);
    justMarkedIds.value = updated;
  }, FLASH_MS);
};

// Single store watcher — not tied to any component lifecycle.
if (typeof store.watch === 'function') {
  store.watch(
    (_state, getters) => [getters.getCurrentAccountId, getters.getCurrentUserID],
    () => {
      currentScopeKey = null;
      ensureLoaded();
    },
    { immediate: true }
  );
}

/**
 * Local-only attachment download tracking (count + lastDownloadedAt per attachment).
 * Scoped by account + user so agents on the same browser do not share state.
 */
export const useAttachmentDownloadState = () => {
  ensureLoaded();

  const isDownloaded = attachmentId => {
    ensureLoaded();
    if (attachmentId == null) return false;
    return (downloadRecords.value[String(attachmentId)]?.count || 0) > 0;
  };

  const downloadCount = attachmentId => {
    ensureLoaded();
    if (attachmentId == null) return 0;
    return downloadRecords.value[String(attachmentId)]?.count || 0;
  };

  const isJustMarked = attachmentId => {
    if (attachmentId == null) return false;
    return justMarkedIds.value.has(String(attachmentId));
  };

  const markDownloaded = attachmentId => {
    const { accountId, userId } = ensureLoaded();
    if (attachmentId == null) return;

    const key = String(attachmentId);
    const previous = downloadRecords.value[key] || { count: 0 };

    downloadRecords.value = {
      ...downloadRecords.value,
      [key]: {
        count: (previous.count || 0) + 1,
        lastDownloadedAt: Date.now(),
      },
    };

    persistRecords(accountId, userId);
    flashMarked(attachmentId);
  };

  /** Mark as handled without downloading (count stays at least 1). */
  const markAsHandled = attachmentId => {
    const { accountId, userId } = ensureLoaded();
    if (attachmentId == null) return;

    const key = String(attachmentId);
    const previous = downloadRecords.value[key];
    if (previous?.count > 0) return;

    downloadRecords.value = {
      ...downloadRecords.value,
      [key]: {
        count: 1,
        lastDownloadedAt: Date.now(),
      },
    };

    persistRecords(accountId, userId);
    flashMarked(attachmentId);
  };

  const clearDownloaded = attachmentId => {
    const { accountId, userId } = ensureLoaded();
    if (attachmentId == null) return;

    const key = String(attachmentId);
    if (!downloadRecords.value[key]) return;

    const next = { ...downloadRecords.value };
    delete next[key];
    downloadRecords.value = next;
    persistRecords(accountId, userId);
  };

  /**
   * Tooltip: Download | Downloaded · Download again | Downloaded · N× · Download again
   * @param {Function} t - vue-i18n t
   * @param {string|number} attachmentId
   * @param {'CONVERSATION'|'CONVERSATION_SIDEBAR.SHARED_FILES'} ns
   */
  const downloadActionTooltip = (t, attachmentId, ns = 'CONVERSATION') => {
    const count = downloadCount(attachmentId);
    if (count <= 0) return t(`${ns}.DOWNLOAD`);

    const status =
      count === 1
        ? t(`${ns}.DOWNLOADED`)
        : t(`${ns}.DOWNLOADED_COUNT`, { count });

    return `${status} · ${t(`${ns}.DOWNLOAD_AGAIN`)}`;
  };

  const contextActionTooltip = (t, attachmentId, ns = 'CONVERSATION') => {
    if (isDownloaded(attachmentId)) return t(`${ns}.CLEAR_DOWNLOAD_MARK`);
    return t(`${ns}.MARK_AS_HANDLED`);
  };

  return {
    isDownloaded,
    downloadCount,
    isJustMarked,
    markDownloaded,
    markAsHandled,
    clearDownloaded,
    downloadActionTooltip,
    contextActionTooltip,
  };
};
