import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import useAutomationValues from 'dashboard/composables/useAutomationValues';
import { useEditableAutomation } from 'dashboard/composables/useEditableAutomation';
import {
  validateSingleFilter,
  validateSingleAction,
} from 'dashboard/helper/validations';
import actionQueryGenerator from 'dashboard/helper/actionQueryGenerator';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  DEFAULT_WORKFLOW_RULE,
  WORKFLOW_ACTION_TYPES,
  WORKFLOW_CONDITIONS,
  WORKFLOW_STATUS_OPTIONS,
} from 'dashboard/routes/dashboard/settings/conversationRules/constants';
import { isInactivityTrigger } from 'dashboard/routes/dashboard/settings/conversationRules/helpers/triggerHelper';

const MAX_DURATION_MINUTES = 1_439_856;

const SUPPORTED_CONTACT_INBOX_TYPES = [
  INBOX_TYPES.WHATSAPP,
  INBOX_TYPES.WAVOIP,
  INBOX_TYPES.TWILIO,
  INBOX_TYPES.SMS,
  INBOX_TYPES.EMAIL,
  INBOX_TYPES.API,
  INBOX_TYPES.WEB,
];

const PHONE_REQUIRED_TYPES = [
  INBOX_TYPES.WHATSAPP,
  INBOX_TYPES.WAVOIP,
  INBOX_TYPES.TWILIO,
  INBOX_TYPES.SMS,
];


const clonePlain = value => JSON.parse(JSON.stringify(value));

const toIds = values => {
  if (!Array.isArray(values) || !values.length) return [];
  return values.map(value =>
    value && typeof value === 'object' ? value.id : value
  );
};

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
  const store = useStore();
  const { getConditionDropdownValues, getActionDropdownValues } =
    useAutomationValues();
  const { formatAutomation } = useEditableAutomation();

  const rule = ref(
    startValue ? clonePlain(startValue) : clonePlain(DEFAULT_WORKFLOW_RULE)
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
        if (triggerType === 'conversation_inactivity') {
          rule.value.actions = (rule.value.actions || []).filter(
            action => action.action_name !== 'resolve_conversation'
          );
        } else {
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
    // Match automation: clear params only — action_name was already set via v-model.
    const name = rule.value.actions[index].action_name;
    rule.value.actions[index] = {
      action_name: name,
      action_params:
        name === 'send_message_to_contact' ? [null, null, ''] : [],
      counts_as_agent_reply: false,
    };
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

    const contactMessageIncomplete = actions.some(action => {
      if (action.action_name !== 'send_message_to_contact') return false;
      const [inboxId, contactId, message] = action.action_params || [];
      return !inboxId || !contactId || !String(message || '').trim();
    });
    if (contactMessageIncomplete) {
      errors.actions = t(
        'CONVERSATION_RULES.VALIDATION.CONTACT_MESSAGE_REQUIRED'
      );
    }

    const contactChannelMismatch = actions.some(action => {
      if (action.action_name !== 'send_message_to_contact') return false;
      const [inboxId, contactValue] = action.action_params || [];
      const inbox = (store.getters['inboxes/getInboxes'] || []).find(
        item => item.id === Number(inboxId?.id ?? inboxId)
      );
      if (!inbox) return true;
      if (!SUPPORTED_CONTACT_INBOX_TYPES.includes(inbox.channel_type)) {
        return true;
      }

      if (typeof contactValue !== 'object' || !contactValue) return false;

      const hasPhone = !!(contactValue.phone_number || contactValue.phoneNumber);
      const hasEmail = !!contactValue.email;

      if (PHONE_REQUIRED_TYPES.includes(inbox.channel_type) && !hasPhone) {
        return true;
      }
      if (inbox.channel_type === INBOX_TYPES.EMAIL && !hasEmail) {
        return true;
      }
      return false;
    });
    if (contactChannelMismatch && !contactMessageIncomplete) {
      errors.actions = t(
        'CONVERSATION_RULES.VALIDATION.CONTACT_CHANNEL_MISMATCH'
      );
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

  const normalizeActionsForPayload = actions => {
    return (actions || []).map(action => {
      if (action.action_name === 'send_message_to_contact') {
        const [inboxId, contactId, message] = action.action_params || [];
        const toId = value => {
          if (value && typeof value === 'object') return Number(value.id);
          return value ? Number(value) : null;
        };

        return {
          action_name: action.action_name,
          action_params: [toId(inboxId), toId(contactId), message || ''],
          counts_as_agent_reply: false,
        };
      }

      const [normalized] = actionQueryGenerator([
        {
          action_name: action.action_name,
          action_params: action.action_params || [],
        },
      ]);

      return {
        action_name: normalized.action_name,
        action_params: normalized.action_params,
        counts_as_agent_reply: action.counts_as_agent_reply || false,
      };
    });
  };

  const buildPayload = () => {
    const inboxIds = toIds(rule.value.inbox_ids);
    const statusIds = toIds(rule.value.options?.statuses);
    const conditions = rule.value.conditions || [];
    const normalizedConditions = conditions.length
      ? filterQueryGenerator(conditions).payload
      : [];

    const payload = {
      name: rule.value.name,
      description: rule.value.description,
      active: rule.value.active,
      position: rule.value.position,
      trigger_type: rule.value.trigger_type,
      duration_minutes: rule.value.duration_minutes,
      inbox_ids: inboxIds.length ? inboxIds : null,
      conditions: normalizedConditions,
      actions: normalizeActionsForPayload(rule.value.actions),
      options: {
        statuses: statusIds.length ? statusIds : ['open'],
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

  // MultiSelect/AutomationActionInput expect objects; API stores scalar ids.
  const hydrateRuleForForm = ({ inboxOptions = [], statusLabelFn } = {}) => {
    const inboxIds = rule.value.inbox_ids || [];
    if (inboxIds.length && typeof inboxIds[0] !== 'object') {
      rule.value.inbox_ids = inboxOptions.filter(option =>
        inboxIds.map(Number).includes(Number(option.id))
      );
    } else if (!Array.isArray(rule.value.inbox_ids)) {
      rule.value.inbox_ids = [];
    }

    const statuses = rule.value.options?.statuses || [];
    if (statuses.length && typeof statuses[0] !== 'object') {
      const statusOptions = WORKFLOW_STATUS_OPTIONS.map(item => ({
        id: item.id,
        name: statusLabelFn ? statusLabelFn(item.id) : item.id,
      }));
      rule.value.options.statuses = statusOptions.filter(option =>
        statuses.includes(option.id)
      );
    }

    // Only API-backed rules need action/condition object hydration.
    if (!rule.value.id) return;

    const manifested = formatAutomation(
      {
        ...rule.value,
        event_name: 'conversation_created',
        conditions: rule.value.conditions || [],
        actions: (rule.value.actions || []).map(action => ({
          ...action,
          action_params: action.action_params || [],
        })),
      },
      [],
      { conversation_created: { conditions: WORKFLOW_CONDITIONS } },
      WORKFLOW_ACTION_TYPES
    );

    rule.value.conditions = manifested.conditions;
    rule.value.actions = manifested.actions.map(action => {
      if (action.action_name !== 'send_message_to_contact') return action;
      return {
        ...action,
        action_params: action.action_params?.length
          ? action.action_params
          : [null, null, ''],
      };
    });
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
    hydrateRuleForForm,
  };
}
