import { ref, unref } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import wootConstants from 'dashboard/constants/globals';

export function useBulkActions() {
  const store = useStore();
  const { t } = useI18n();
  const { checkMissingAttributes } = useConversationRequiredAttributes();

  const selectedConversations = useMapGetter(
    'bulkActions/getSelectedConversationIds'
  );
  const selectedInboxes = ref([]);
  // FORK: assignme - Tracks pending conversation IDs to prevent concurrent assignment requests.
  // Uses Set for O(1) lookup performance during rapid user interactions.
  const pendingAssignConversationIds = ref(new Set());

  function selectConversation(conversationId, inboxId) {
    store.dispatch('bulkActions/setSelectedConversationIds', conversationId);
    selectedInboxes.value = [...selectedInboxes.value, inboxId];
  }

  function deSelectConversation(conversationId, inboxId) {
    store.dispatch('bulkActions/removeSelectedConversationIds', conversationId);
    // Only remove one instance of the inboxId, not all
    // This handles the case where multiple conversations from the same inbox are selected
    const index = selectedInboxes.value.indexOf(inboxId);
    if (index > -1) {
      selectedInboxes.value = [
        ...selectedInboxes.value.slice(0, index),
        ...selectedInboxes.value.slice(index + 1),
      ];
    }
  }

  function resetBulkActions() {
    store.dispatch('bulkActions/clearSelectedConversationIds');
    selectedInboxes.value = [];
  }

  function selectAllConversations(check, conversationList) {
    const availableConversations = unref(conversationList);
    if (check) {
      store.dispatch(
        'bulkActions/setSelectedConversationIds',
        availableConversations.map(item => item.id)
      );
      selectedInboxes.value = availableConversations.map(item => item.inbox_id);
    } else {
      resetBulkActions();
    }
  }

  function isConversationSelected(id) {
    return selectedConversations.value.includes(id);
  }

  // FORK: assignme - Keep a consistent payload shape for single and multiple assignment paths.
  function normalizeConversationIds(conversationId) {
    if (conversationId) {
      return Array.isArray(conversationId) ? conversationId : [conversationId];
    }

    return selectedConversations.value;
  }

  // FORK: assignme - Used by conversation cards to render loading from real request state.
  function isAssignPending(conversationId) {
    return pendingAssignConversationIds.value.has(conversationId);
  }

  function markAssignPending(conversationIds) {
    pendingAssignConversationIds.value = new Set([
      ...pendingAssignConversationIds.value,
      ...conversationIds,
    ]);
  }

  function clearAssignPending(conversationIds) {
    const nextPending = new Set(pendingAssignConversationIds.value);
    conversationIds.forEach(id => nextPending.delete(id));
    pendingAssignConversationIds.value = nextPending;
  }

  // Same method used in context menu, conversationId being passed from there.
  async function onAssignAgent(agent, conversationId = null) {
    const conversationIds = normalizeConversationIds(conversationId);
    if (!conversationIds.length) return;

    const assigneeId = agent?.id ?? null;
    const assigneeName =
      agent?.name || t('CONVERSATION_SIDEBAR.SELECT.PLACEHOLDER');

    if (conversationIds.some(id => isAssignPending(id))) return;

    markAssignPending(conversationIds);

    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: conversationIds,
        fields: {
          assignee_id: assigneeId,
        },
      });

      // FORK: assignme - Intentionally NOT doing optimistic UI update here.
      // Optimistic assignee mutation conflicts with DynamicScroller reconciliation when item
      // changes lists (unassigned -> assigned), causing null vnode errors. We rely on ActionCable
      // to broadcast the change (200-500ms latency is acceptable for stability).

      store.dispatch('bulkActions/clearSelectedConversationIds');
      if (conversationId) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.SUCCESFUL', {
            agentName: assigneeName,
            conversationId: conversationIds[0],
          })
        );
      } else {
        useAlert(t('BULK_ACTION.ASSIGN_SUCCESFUL'));
      }
    } catch (err) {
      const status = err?.response?.status;
      if (status === 403) {
        useAlert(
          t(
            'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.PERMISSION_DENIED'
          )
        );
      } else if (status === 422) {
        useAlert(
          t(
            'CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.VALIDATION_FAILED'
          )
        );
      } else if (status === 408 || status === 504) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.TIMEOUT')
        );
      } else {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.AGENT_ASSIGNMENT.FAILED')
        );
      }
    } finally {
      clearAssignPending(conversationIds);
    }
  }

  // Same method used in context menu, conversationId being passed from there.
  async function onAssignLabels(newLabels, conversationId = null) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: conversationId || selectedConversations.value,
        labels: {
          add: newLabels,
        },
      });
      store.dispatch('bulkActions/clearSelectedConversationIds');
      if (conversationId) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.LABEL_ASSIGNMENT.SUCCESFUL', {
            labelName: newLabels[0],
            conversationId,
          })
        );
      } else {
        useAlert(t('BULK_ACTION.LABELS.ASSIGN_SUCCESFUL'));
      }
    } catch (err) {
      useAlert(t('BULK_ACTION.LABELS.ASSIGN_FAILED'));
    }
  }

  // Used by both context menu and bulk action bar.
  async function onRemoveLabels(labelsToRemove, conversationId = null) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: conversationId || selectedConversations.value,
        labels: {
          remove: labelsToRemove,
        },
      });

      // Context-menu remove should not disturb an existing bulk selection.
      if (conversationId) {
        useAlert(
          t('CONVERSATION.CARD_CONTEXT_MENU.API.LABEL_REMOVAL.SUCCESFUL', {
            labelName: labelsToRemove[0],
            conversationId,
          })
        );
      } else {
        store.dispatch('bulkActions/clearSelectedConversationIds');
        useAlert(t('BULK_ACTION.LABELS.REMOVE_SUCCESFUL'));
      }
    } catch (err) {
      useAlert(
        conversationId
          ? t('CONVERSATION.CARD_CONTEXT_MENU.API.LABEL_REMOVAL.FAILED')
          : t('BULK_ACTION.LABELS.REMOVE_FAILED')
      );
    }
  }

  async function onAssignTeamsForBulk(team) {
    try {
      await store.dispatch('bulkActions/process', {
        type: 'Conversation',
        ids: selectedConversations.value,
        fields: {
          team_id: team.id,
        },
      });
      store.dispatch('bulkActions/clearSelectedConversationIds');
      useAlert(t('BULK_ACTION.TEAMS.ASSIGN_SUCCESFUL'));
    } catch (err) {
      useAlert(t('BULK_ACTION.TEAMS.ASSIGN_FAILED'));
    }
  }

  async function onUpdateConversations(status, snoozedUntil) {
    if (selectedConversations.value.length === 0) return;

    let conversationIds = selectedConversations.value;
    let skippedCount = 0;

    // If resolving, check for required attributes
    if (status === wootConstants.STATUS_TYPE.RESOLVED) {
      const { validIds, skippedIds } = selectedConversations.value.reduce(
        (acc, id) => {
          const conversation = store.getters.getConversationById(id);
          const currentCustomAttributes = conversation?.custom_attributes || {};
          const { hasMissing } = checkMissingAttributes(
            currentCustomAttributes
          );

          if (!hasMissing) {
            acc.validIds.push(id);
          } else {
            acc.skippedIds.push(id);
          }
          return acc;
        },
        { validIds: [], skippedIds: [] }
      );

      conversationIds = validIds;
      skippedCount = skippedIds.length;

      if (skippedCount > 0 && validIds.length === 0) {
        // All conversations have missing attributes
        useAlert(
          t('BULK_ACTION.RESOLVE.ALL_MISSING_ATTRIBUTES') ||
            'Cannot resolve conversations due to missing required attributes'
        );
        return;
      }
    }

    try {
      if (conversationIds.length > 0) {
        await store.dispatch('bulkActions/process', {
          type: 'Conversation',
          ids: conversationIds,
          fields: {
            status,
          },
          snoozed_until: snoozedUntil,
        });
      }

      store.dispatch('bulkActions/clearSelectedConversationIds');

      if (skippedCount > 0) {
        useAlert(t('BULK_ACTION.RESOLVE.PARTIAL_SUCCESS'));
      } else {
        useAlert(t('BULK_ACTION.UPDATE.UPDATE_SUCCESFUL'));
      }
    } catch (err) {
      useAlert(t('BULK_ACTION.UPDATE.UPDATE_FAILED'));
    }
  }

  return {
    selectedConversations,
    selectedInboxes,
    selectConversation,
    deSelectConversation,
    selectAllConversations,
    resetBulkActions,
    isConversationSelected,
    isAssignPending,
    onAssignAgent,
    onAssignLabels,
    onRemoveLabels,
    onAssignTeamsForBulk,
    onUpdateConversations,
  };
}
