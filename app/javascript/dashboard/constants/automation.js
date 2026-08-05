export const DEFAULT_MESSAGE_CREATED_CONDITION = [
  {
    attribute_key: 'message_type',
    filter_operator: 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

export const DEFAULT_CONVERSATION_CONDITION = [
  {
    attribute_key: 'browser_language',
    filter_operator: 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

export const DEFAULT_OTHER_CONDITION = [
  {
    attribute_key: 'status',
    filter_operator: 'equal_to',
    values: '',
    query_operator: 'and',
    custom_attribute_type: '',
  },
];

export const DEFAULT_ACTIONS = [
  {
    action_name: 'assign_agent',
    action_params: [],
  },
];

export const MESSAGE_CONDITION_VALUES = [
  {
    id: 'incoming',
    name: 'Incoming',
    i18nKey: 'INCOMING',
  },
  {
    id: 'outgoing',
    name: 'Outgoing',
    i18nKey: 'OUTGOING',
  },
];

export const PRIORITY_CONDITION_VALUES = [
  {
    id: 'nil',
    name: 'None',
    i18nKey: 'NONE',
  },
  {
    id: 'low',
    name: 'Low',
    i18nKey: 'LOW',
  },
  {
    id: 'medium',
    name: 'Medium',
    i18nKey: 'MEDIUM',
  },
  {
    id: 'high',
    name: 'High',
    i18nKey: 'HIGH',
  },
  {
    id: 'urgent',
    name: 'Urgent',
    i18nKey: 'URGENT',
  },
];

// FORK: automation condition — who opened/created the conversation episode
export const OPENED_BY_CONDITION_VALUES = [
  {
    id: 'contact',
    i18nKey: 'CONTACT',
  },
  {
    id: 'agent',
    i18nKey: 'AGENT',
  },
  {
    id: 'phone',
    i18nKey: 'PHONE',
  },
];

// FORK: Liquid-aligned chips for automation send_message / add_private_note
export const AUTOMATION_MESSAGE_VARIABLES = [
  'conversation.id',
  'conversation.display_id',
  'contact.name',
  'contact.first_name',
  'contact.last_name',
  'contact.email',
  'contact.phone_number',
  'agent.name',
  'inbox.name',
  'account.name',
  'rule.name',
];

export const AUTOMATION_MESSAGE_VARIABLE_PREVIEW = {
  'conversation.id': '1234',
  'conversation.display_id': '1234',
  'contact.name': 'João Silva',
  'contact.first_name': 'João',
  'contact.last_name': 'Silva',
  'contact.email': 'joao@example.com',
  'contact.phone_number': '+5566999000000',
  'contact.phone': '+5566999000000',
  'agent.name': 'Maria',
  'inbox.name': 'WhatsApp',
  'account.name': 'Acme',
  'rule.name': 'Boas vindas',
  'macro.name': 'Macro exemplo',
};

// FORK: Liquid filter shortcut chips (snippets are Liquid English, labels via i18n)
export const AUTOMATION_LIQUID_FILTER_SNIPPETS = [
  'contact.email | default: "sem email"',
  'contact.name | default: "cliente"',
  'contact.phone_number | default: ""',
];
