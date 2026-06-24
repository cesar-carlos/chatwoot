import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import useAutomationValues from 'dashboard/composables/useAutomationValues';
import {
  validateSingleFilter,
  validateSingleAction,
} from 'dashboard/helper/validations';
import {
  DEFAULT_WORKFLOW_RULE,
  WORKFLOW_CONDITIONS,
} from 'dashboard/routes/dashboard/settings/conversationRules/constants';
import { isInactivityTrigger } from 'dashboard/routes/dashboard/settings/conversationRules/helpers/triggerHelper';

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

  const fieldErrors = ref({});

  if (!startValue?.id) {
    const maxPosition = existingRules.reduce(
      (max, item) => Math.max(max, item.position ?? 0),
      -1
    );
    rule.value.position = maxPosition + 1;
  }

  const clearFieldError = field => {
    if (fieldErrors.value[field]) {
      const next = { ...fieldErrors.value };
      delete next[field];
      fieldErrors.value = next;
    }
  };

  watch(
    () => rule.value.trigger_type,
    (triggerType, previousType) => {
      if (!previousType || triggerType === previousType) return;

      if (isInactivityTrigger(triggerType)) {
        rule.value.options = {
          statuses: ['open'],
          require_no_first_reply: false,
          respect_business_hours:
            rule.value.options?.respect_business_hours || false,
        };
        if (triggerType !== 'conversation_inactivity') {
          rule.value.ignore_waiting = false;
          rule.value.resolve_on_match = false;
          rule.value.message = '';
        }
      } else {
        rule.value.ignore_waiting = false;
        rule.value.resolve_on_match = false;
        rule.value.message = '';
        if (triggerType === 'first_response_overdue') {
          rule.value.options = {
            statuses: rule.value.options?.statuses || ['open'],
            require_no_first_reply: true,
            respect_business_hours:
              rule.value.options?.respect_business_hours || false,
          };
        } else if (triggerType === 'agent_no_reply') {
          rule.value.options = {
            statuses: rule.value.options?.statuses || ['open'],
            require_no_first_reply:
              rule.value.options?.require_no_first_reply || false,
            respect_business_hours:
              rule.value.options?.respect_business_hours || false,
          };
        } else if (triggerType === 'pending_stale') {
          rule.value.options = {
            statuses: ['pending'],
            require_no_first_reply: false,
            respect_business_hours:
              rule.value.options?.respect_business_hours || false,
          };
        } else {
          rule.value.options = {
            statuses: ['open'],
            require_no_first_reply: false,
            respect_business_hours:
              rule.value.options?.respect_business_hours || false,
          };
        }
      }
    }
  );

  watch(
    () => rule.value.name,
    () => clearFieldError('name')
  );

  watch(
    () => rule.value.duration_minutes,
    () => clearFieldError('duration')
  );

  watch(
    () => rule.value.actions,
    () => clearFieldError('actions'),
    { deep: true }
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
    const errors = {};

    if (!rule.value.name?.trim()) {
      errors.name = t('CONVERSATION_RULES.VALIDATION.NAME_REQUIRED');
    }

    if (!rule.value.duration_minutes || rule.value.duration_minutes < 10) {
      errors.duration = t('CONVERSATION_RULES.VALIDATION.DURATION_MIN');
    } else if (rule.value.duration_minutes > MAX_DURATION_MINUTES) {
      errors.duration = t('CONVERSATION_RULES.VALIDATION.DURATION_MAX');
    }

    const conditions = rule.value.conditions || [];
    const conditionError = conditions
      .map(condition => validateSingleFilter(condition))
      .find(Boolean);
    if (conditionError) {
      errors.conditions = t(`AUTOMATION.ERRORS.${conditionError}`);
    }

    const actions = rule.value.actions || [];
    const actionError = actions
      .map(action => validateSingleAction(action))
      .find(Boolean);
    if (actionError) {
      errors.actions = t(`AUTOMATION.ERRORS.${actionError}`);
    }

    if (isInactivityTrigger(rule.value.trigger_type)) {
      const hasOutcome =
        actions.length > 0 ||
        (rule.value.trigger_type === 'conversation_inactivity' &&
          (rule.value.resolve_on_match || rule.value.message?.trim()));
      if (!hasOutcome) {
        errors.actions = t('CONVERSATION_RULES.VALIDATION.INACTIVITY_OUTCOME');
      }
    } else {
      const hasResolve = actions.some(
        action => action.action_name === 'resolve_conversation'
      );
      if (!actions.length && !hasResolve) {
        errors.actions = t(
          'CONVERSATION_RULES.VALIDATION.AGENT_NO_REPLY_ACTIONS'
        );
      }
    }

    fieldErrors.value = errors;
    return Object.keys(errors).length === 0;
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
    } else if (payload.trigger_type === 'agent_no_reply') {
      payload.ignore_waiting = false;
      payload.resolve_on_match = false;
      payload.message = null;
    } else if (payload.trigger_type === 'first_response_overdue') {
      payload.ignore_waiting = false;
      payload.resolve_on_match = false;
      payload.message = null;
      payload.options.require_no_first_reply = true;
    } else if (payload.trigger_type === 'pending_stale') {
      payload.ignore_waiting = false;
      payload.resolve_on_match = false;
      payload.message = null;
      payload.options.require_no_first_reply = false;
      payload.options.statuses = ['pending'];
    } else {
      // unassigned_too_long, customer_no_reply
      payload.ignore_waiting = false;
      payload.resolve_on_match = false;
      payload.message = null;
      payload.options.require_no_first_reply = false;
      payload.options.statuses = ['open'];
    }

    return payload;
  };

  return {
    rule,
    fieldErrors,
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
