// FORK: warn when enabling single-history if conversation_created automations apply
import { computed, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';

const CONVERSATION_CREATED_EVENT = 'conversation_created';

const normalizeInboxIds = values => (values || []).map(value => String(value));

export const automationAppliesToInbox = (rule, inboxId) => {
  if (!rule?.active || rule.event_name !== CONVERSATION_CREATED_EVENT) {
    return false;
  }

  const inboxCondition = rule.conditions?.find(
    condition => condition.attribute_key === 'inbox_id'
  );

  if (!inboxCondition) return true;

  const inboxIds = normalizeInboxIds(inboxCondition.values);
  const inboxIdStr = String(inboxId);

  if (inboxCondition.filter_operator === 'equal_to') {
    return inboxIds.length === 0 || inboxIds.includes(inboxIdStr);
  }

  if (inboxCondition.filter_operator === 'not_equal_to') {
    return inboxIds.length === 0 || !inboxIds.includes(inboxIdStr);
  }

  return true;
};

export const findConversationCreatedAutomationsForInbox = (
  automations,
  inboxId
) => automations.filter(rule => automationAppliesToInbox(rule, inboxId));

export const useSingleHistoryAutomationWarning = inboxId => {
  const store = useStore();

  onMounted(() => {
    const automations = store.getters['automations/getAutomations'];
    if (!automations.length) {
      store.dispatch('automations/get');
    }
  });

  const isFetching = computed(
    () => store.getters['automations/getUIFlags'].isFetching
  );

  const matchingRules = computed(() => {
    if (!inboxId.value) return [];

    return findConversationCreatedAutomationsForInbox(
      store.getters['automations/getAutomations'],
      inboxId.value
    );
  });

  const showAutomationWarning = computed(() => matchingRules.value.length > 0);

  return {
    matchingRules,
    showAutomationWarning,
    isFetching,
  };
};
