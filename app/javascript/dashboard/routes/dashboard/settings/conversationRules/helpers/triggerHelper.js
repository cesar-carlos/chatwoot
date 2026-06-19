import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  INACTIVITY_TRIGGERS,
  RESPONSE_TRIGGERS,
  WORKFLOW_TRIGGERS,
} from '../constants';

export function isInactivityTrigger(triggerType) {
  return INACTIVITY_TRIGGERS.includes(triggerType);
}

export function isResponseTrigger(triggerType) {
  return RESPONSE_TRIGGERS.includes(triggerType);
}

export function getDurationLabelKey(triggerType) {
  const keys = {
    conversation_inactivity:
      'CONVERSATION_RULES.FORM.DURATION_LABELS.INACTIVITY',
    customer_no_reply:
      'CONVERSATION_RULES.FORM.DURATION_LABELS.CUSTOMER_NO_REPLY',
    agent_no_reply: 'CONVERSATION_RULES.FORM.DURATION_LABELS.AGENT_NO_REPLY',
    first_response_overdue:
      'CONVERSATION_RULES.FORM.DURATION_LABELS.FIRST_RESPONSE',
    unassigned_too_long: 'CONVERSATION_RULES.FORM.DURATION_LABELS.UNASSIGNED',
    pending_stale: 'CONVERSATION_RULES.FORM.DURATION_LABELS.PENDING',
  };
  return keys[triggerType] || 'CONVERSATION_RULES.FORM.DURATION';
}

export function getAvailableTriggers(isFeatureEnabled, accountId) {
  return WORKFLOW_TRIGGERS.filter(trigger => {
    if (!trigger.featureFlag) return true;
    return isFeatureEnabled(accountId, trigger.featureFlag);
  });
}

export function getTriggerTab(triggerType) {
  return WORKFLOW_TRIGGERS.find(t => t.key === triggerType)?.tab || 'all';
}

export function filterRulesByTab(rules, tab) {
  if (!tab || tab === 'all') return rules;
  return rules.filter(rule => getTriggerTab(rule.trigger_type) === tab);
}

export { FEATURE_FLAGS };
