import {
  OPERATOR_TYPES_1,
  OPERATOR_TYPES_3,
} from 'dashboard/routes/dashboard/settings/automation/operators';
import { AUTOMATION_ACTION_TYPES } from 'dashboard/routes/dashboard/settings/automation/constants';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

export const WORKFLOW_TRIGGERS = [
  {
    key: 'conversation_inactivity',
    value: 'CONVERSATION_INACTIVITY',
    icon: 'i-lucide-moon',
    featureFlag: FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS,
    tab: 'inactivity',
  },
  {
    key: 'customer_no_reply',
    value: 'CUSTOMER_NO_REPLY',
    icon: 'i-lucide-message-circle-off',
    featureFlag: FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS,
    tab: 'inactivity',
  },
  {
    key: 'agent_no_reply',
    value: 'AGENT_NO_REPLY',
    icon: 'i-lucide-clock',
    featureFlag: FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES,
    tab: 'response',
  },
  {
    key: 'first_response_overdue',
    value: 'FIRST_RESPONSE_OVERDUE',
    icon: 'i-lucide-user-x',
    featureFlag: FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES,
    tab: 'response',
  },
  {
    key: 'unassigned_too_long',
    value: 'UNASSIGNED_TOO_LONG',
    icon: 'i-lucide-inbox',
    featureFlag: FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES,
    tab: 'response',
  },
  {
    key: 'pending_stale',
    value: 'PENDING_STALE',
    icon: 'i-lucide-hourglass',
    featureFlag: FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES,
    tab: 'response',
  },
];

export const WORKFLOW_TRIGGER_TABS = [
  { key: 'all', labelKey: 'CONVERSATION_RULES.TABS.ALL' },
  { key: 'inactivity', labelKey: 'CONVERSATION_RULES.TABS.INACTIVITY' },
  { key: 'response', labelKey: 'CONVERSATION_RULES.TABS.RESPONSE' },
];

export const DURATION_PRESETS = [
  { minutes: 15, labelKey: 'CONVERSATION_RULES.FORM.PRESETS.MIN_15' },
  { minutes: 60, labelKey: 'CONVERSATION_RULES.FORM.PRESETS.HOUR_1' },
  { minutes: 240, labelKey: 'CONVERSATION_RULES.FORM.PRESETS.HOURS_4' },
  { minutes: 1440, labelKey: 'CONVERSATION_RULES.FORM.PRESETS.HOURS_24' },
];

export const INACTIVITY_TRIGGERS = [
  'conversation_inactivity',
  'customer_no_reply',
];

export const RESPONSE_TRIGGERS = [
  'agent_no_reply',
  'first_response_overdue',
  'unassigned_too_long',
  'pending_stale',
];

export const WORKFLOW_CONDITIONS = [
  {
    key: 'assignee_id',
    name: 'ASSIGNEE_NAME',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'team_id',
    name: 'TEAM_NAME',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'labels',
    name: 'LABELS',
    inputType: 'multi_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'priority',
    name: 'PRIORITY',
    inputType: 'multi_select',
    filterOperators: OPERATOR_TYPES_1,
  },
];

const DISALLOWED_ACTIONS = [
  'mute_conversation',
  'snooze_conversation',
  'open_conversation',
  'pending_conversation',
  'change_status',
  'send_attachment',
  'add_sla',
];

export const WORKFLOW_ONLY_ACTIONS = [
  {
    key: 'send_message_to_contact',
    label: 'SEND_MESSAGE_TO_CONTACT',
    inputType: 'contact_message',
  },
];

export const WORKFLOW_ACTION_TYPES = [
  ...AUTOMATION_ACTION_TYPES.filter(
    action => !DISALLOWED_ACTIONS.includes(action.key)
  ),
  ...WORKFLOW_ONLY_ACTIONS,
];

export const WORKFLOW_STATUS_OPTIONS = [
  { id: 'open', name: 'OPEN' },
  { id: 'pending', name: 'PENDING' },
];

export const DEFAULT_WORKFLOW_RULE = {
  name: '',
  description: '',
  active: true,
  position: 0,
  trigger_type: 'conversation_inactivity',
  duration_minutes: 60,
  inbox_ids: [],
  ignore_waiting: false,
  resolve_on_match: false,
  message: '',
  conditions: [],
  actions: [],
  options: {
    statuses: ['open'],
    require_no_first_reply: false,
    respect_business_hours: false,
  },
};

// FORK: synthetic automation events triggered by workflow rules
export const WORKFLOW_AUTOMATION_EVENTS = [
  {
    key: 'conversation_inactivity_threshold',
    value: 'CONVERSATION_INACTIVITY_THRESHOLD',
  },
  {
    key: 'conversation_agent_no_reply',
    value: 'CONVERSATION_AGENT_NO_REPLY',
  },
  {
    key: 'conversation_first_response_overdue',
    value: 'CONVERSATION_FIRST_RESPONSE_OVERDUE',
  },
  {
    key: 'conversation_unassigned_too_long',
    value: 'CONVERSATION_UNASSIGNED_TOO_LONG',
  },
  {
    key: 'conversation_pending_stale',
    value: 'CONVERSATION_PENDING_STALE',
  },
  {
    key: 'conversation_customer_no_reply',
    value: 'CONVERSATION_CUSTOMER_NO_REPLY',
  },
];
