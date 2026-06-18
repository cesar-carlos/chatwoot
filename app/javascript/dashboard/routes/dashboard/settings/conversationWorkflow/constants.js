import {
  OPERATOR_TYPES_1,
  OPERATOR_TYPES_3,
} from 'dashboard/routes/dashboard/settings/automation/operators';
import { AUTOMATION_ACTION_TYPES } from 'dashboard/routes/dashboard/settings/automation/constants';

export const WORKFLOW_TRIGGERS = [
  {
    key: 'conversation_inactivity',
    value: 'CONVERSATION_INACTIVITY',
  },
  {
    key: 'agent_no_reply',
    value: 'AGENT_NO_REPLY',
  },
];

export const WORKFLOW_CONDITIONS = [
  {
    key: 'assignee_id',
    name: 'ASSIGNEE_NAME',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_1,
  },
  {
    key: 'team_id',
    name: 'TEAM_NAME',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_1,
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
];

export const WORKFLOW_ACTION_TYPES = AUTOMATION_ACTION_TYPES.filter(
  action => !DISALLOWED_ACTIONS.includes(action.key)
);

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
];
