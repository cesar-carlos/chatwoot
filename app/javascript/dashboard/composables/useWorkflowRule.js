import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import useAutomationValues from 'dashboard/composables/useAutomationValues';
import {
  validateSingleFilter,
  validateSingleAction,
} from 'dashboard/helper/validations';
import {
  DEFAULT_WORKFLOW_RULE,
  WORKFLOW_CONDITIONS,
} from 'dashboard/routes/dashboard/settings/conversationWorkflow/constants';

const MAX_DURATION_MINUTES = 1_439_856;

const defaultCondition = () => ({
  attribute_key: WORKFLOW_CONDITIONS[0].key,
  filter_operator: 'equal_to',
  values: '',
  query_operator: 'and',
  custom_attribute_type: '',
});

const defaultAction = () => ({
  action_name: 'add_label',
  action_params: [],
  counts_as_agent_reply: false,
});

export function useWorkflowRule(startValue = null, existingRules = []) {
  const { t } = useI18n();
  const { getConditionDropdownValues, getActionDropdownValues } =
    useAutomationValues();

  const rule = ref(
    startValue
      ? structuredClone(startValue)
      : structuredClone(DEFAULT_WORKFLOW_RULE)
  );

  if (!startValue?.id) {
    const maxPosition = existingRules.reduce(
      (max, item) => Math.max(max, item.position ?? 0),
      -1
    );
    rule.value.position = maxPosition + 1;
  }

  watch(
    () => rule.value.trigger_type,
    (triggerType, previousType) => {
      if (!previousType || triggerType === previousType) return;

      if (triggerType === 'agent_no_reply') {
        rule.value.ignore_waiting = false;
        rule.value.resolve_on_match = false;
        rule.value.message = '';
      } else {
        rule.value.options = {
          statuses: ['open'],
          require_no_first_reply: false,
          respect_business_hours:
            rule.value.options?.respect_business_hours || false,
        };
      }
    }
  );

  const appendNewCondition = () => {
    rule.value.conditions = [
      ...(rule.value.conditions || []),
      defaultCondition(),
    ];
  };

  const appendNewAction = () => {
    rule.value.actions = [...(rule.value.actions || []), defaultAction()];
  };

  const removeCondition = index => {
    rule.value.conditions = rule.value.conditions.filter((_, i) => i !== index);
  };

  const removeAction = index => {
    rule.value.actions = rule.value.actions.filter((_, i) => i !== index);
  };

  const resetAction = index => {
    rule.value.actions[index] = defaultAction();
  };

  const getWorkflowConditionDropdownValues = type => {
    const attribute = WORKFLOW_CONDITIONS.find(c => c.key === type);
    return getConditionDropdownValues(type, attribute?.inputType);
  };

  const validateRule = () => {
    if (!rule.value.name?.trim()) {
      useAlert(t('CONVERSATION_WORKFLOW.RULES.VALIDATION.NAME_REQUIRED'));
      return false;
    }
    if (!rule.value.duration_minutes || rule.value.duration_minutes < 10) {
      useAlert(t('CONVERSATION_WORKFLOW.RULES.VALIDATION.DURATION_MIN'));
      return false;
    }
    if (rule.value.duration_minutes > MAX_DURATION_MINUTES) {
      useAlert(t('CONVERSATION_WORKFLOW.RULES.VALIDATION.DURATION_MAX'));
      return false;
    }

    const conditions = rule.value.conditions || [];
    const conditionError = conditions
      .map(condition => validateSingleFilter(condition))
      .find(Boolean);
    if (conditionError) {
      useAlert(t(`AUTOMATION.ERRORS.${conditionError}`));
      return false;
    }

    const actions = rule.value.actions || [];
    const actionError = actions
      .map(action => validateSingleAction(action))
      .find(Boolean);
    if (actionError) {
      useAlert(t(`AUTOMATION.ERRORS.${actionError}`));
      return false;
    }

    if (rule.value.trigger_type === 'agent_no_reply') {
      const hasResolve = actions.some(
        action => action.action_name === 'resolve_conversation'
      );
      if (!actions.length && !hasResolve) {
        useAlert(
          t('CONVERSATION_WORKFLOW.RULES.VALIDATION.AGENT_NO_REPLY_ACTIONS')
        );
        return false;
      }
    }

    if (rule.value.trigger_type === 'conversation_inactivity') {
      const hasOutcome =
        actions.length > 0 ||
        rule.value.resolve_on_match ||
        rule.value.message?.trim();
      if (!hasOutcome) {
        useAlert(
          t('CONVERSATION_WORKFLOW.RULES.VALIDATION.INACTIVITY_OUTCOME')
        );
        return false;
      }
    }

    return true;
  };

  const buildPayload = () => {
    const payload = {
      name: rule.value.name,
      description: rule.value.description,
      active: rule.value.active,
      position: rule.value.position,
      trigger_type: rule.value.trigger_type,
      duration_minutes: rule.value.duration_minutes,
      inbox_ids: rule.value.inbox_ids?.length ? rule.value.inbox_ids : null,
      conditions: rule.value.conditions || [],
      actions: (rule.value.actions || []).map(action => ({
        action_name: action.action_name,
        action_params: action.action_params || [],
        counts_as_agent_reply: action.counts_as_agent_reply || false,
      })),
      options: {
        statuses: rule.value.options?.statuses || ['open'],
        require_no_first_reply:
          rule.value.options?.require_no_first_reply || false,
        respect_business_hours:
          rule.value.options?.respect_business_hours || false,
      },
    };

    if (payload.trigger_type === 'conversation_inactivity') {
      payload.ignore_waiting = rule.value.ignore_waiting;
      payload.resolve_on_match = rule.value.resolve_on_match;
      payload.message = rule.value.message;
      payload.options.require_no_first_reply = false;
    } else {
      payload.ignore_waiting = false;
      payload.resolve_on_match = false;
      payload.message = null;
    }

    return payload;
  };

  return {
    rule,
    appendNewCondition,
    appendNewAction,
    removeCondition,
    removeAction,
    resetAction,
    getWorkflowConditionDropdownValues,
    getActionDropdownValues,
    validateRule,
    buildPayload,
  };
}
