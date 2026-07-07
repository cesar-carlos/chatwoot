import { onBeforeUnmount, unref, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';

const POLL_MS = 5000;

export function useEvolutionGoImportStatus(inboxRef) {
  const store = useStore();
  let pollTimer = null;

  function stopPolling() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function isImportRunning(inbox) {
    return inbox?.provider_config?.import_status === 'running';
  }

  async function refreshInbox() {
    const inbox = unref(inboxRef);
    if (!inbox?.id) return;

    await store.dispatch('inboxes/fetchInboxItem', inbox.id);
  }

  function startPollingIfNeeded() {
    stopPolling();
    const inbox = unref(inboxRef);
    if (!isImportRunning(inbox)) return;

    pollTimer = setInterval(() => {
      refreshInbox();
    }, POLL_MS);
  }

  watch(
    () => unref(inboxRef)?.provider_config?.import_status,
    status => {
      if (status === 'running') {
        startPollingIfNeeded();
      } else {
        stopPolling();
      }
    },
    { immediate: true }
  );

  onBeforeUnmount(stopPolling);

  return { refreshInbox, stopPolling };
}
