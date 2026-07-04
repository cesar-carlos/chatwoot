export async function patchWavoipProviderConfig(store, inboxId, patch) {
  await store.dispatch('inboxes/fetchInboxItem', inboxId);
  const serverInbox = store.getters['inboxes/getInbox'](inboxId);
  const existing = { ...(serverInbox?.provider_config || {}) };

  await store.dispatch('inboxes/updateInbox', {
    id: inboxId,
    formData: false,
    channel: {
      provider_config: {
        ...existing,
        ...patch,
      },
    },
  });

  await store.dispatch('inboxes/fetchInboxItem', inboxId);
}
