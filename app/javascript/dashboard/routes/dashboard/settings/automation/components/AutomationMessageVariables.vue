<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import {
  AUTOMATION_MESSAGE_VARIABLES,
  AUTOMATION_MESSAGE_VARIABLE_PREVIEW,
  AUTOMATION_LIQUID_FILTER_SNIPPETS,
} from 'dashboard/constants/automation';

const props = defineProps({
  message: {
    type: String,
    default: '',
  },
  // FORK: 'rule' | 'macro' | 'none' — which executed_by chip to show
  executedByKind: {
    type: String,
    default: 'rule',
  },
});

const emit = defineEmits(['insertVariable']);

const { t } = useI18n();
const { currentAccount } = useAccount();

const inboxes = useMapGetter('inboxes/getInboxes');
const contacts = useMapGetter('contacts/getContacts');

const formatVariableChip = key => `{{${key}}}`;
const formatSnippetChip = snippet => `{{ ${snippet} }}`;

const visibleVariables = computed(() =>
  AUTOMATION_MESSAGE_VARIABLES.filter(key => {
    if (key === 'rule.name') return props.executedByKind === 'rule';
    return true;
  }).concat(props.executedByKind === 'macro' ? ['macro.name'] : [])
);

const previewValues = computed(() => {
  const values = { ...AUTOMATION_MESSAGE_VARIABLE_PREVIEW };
  const account = currentAccount.value;
  if (account?.name) values['account.name'] = account.name;

  const inbox = inboxes.value?.[0];
  if (inbox?.name) values['inbox.name'] = inbox.name;

  const contact = contacts.value?.[0];
  if (contact) {
    const name = contact.name || contact.email || '';
    if (name) {
      values['contact.name'] = name;
      const parts = name.split(/\s+/).filter(Boolean);
      values['contact.first_name'] = parts[0] || name;
      values['contact.last_name'] =
        parts.length > 1 ? parts[parts.length - 1] : '';
    }
    if (contact.email) values['contact.email'] = contact.email;
    const phone = contact.phone_number || contact.phoneNumber;
    if (phone) {
      values['contact.phone_number'] = phone;
      values['contact.phone'] = phone;
    }
  }

  return values;
});

const messagePreview = computed(() => {
  if (!props.message) return '';

  return props.message.replace(
    /\{\{\s*([^}]+?)\s*\}\}/g,
    (match, expression) => {
      const key = expression.trim();
      // Simple keys only for sample preview (skip filter expressions)
      if (Object.prototype.hasOwnProperty.call(previewValues.value, key)) {
        return previewValues.value[key];
      }
      return match;
    }
  );
});

const insertVariable = key => {
  emit('insertVariable', formatVariableChip(key));
};

const insertSnippet = snippet => {
  emit('insertVariable', formatSnippetChip(snippet));
};
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <div class="flex flex-wrap gap-1.5">
      <button
        v-for="variable in visibleVariables"
        :key="variable"
        type="button"
        class="text-xs px-2 py-1 rounded-md bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3 font-mono"
        @click="insertVariable(variable)"
      >
        {{ formatVariableChip(variable) }}
      </button>
    </div>
    <p class="text-xs text-n-slate-11">
      {{ t('AUTOMATION.ACTION.VARIABLES.HINT') }}
    </p>
    <p class="text-xs text-n-slate-10">
      {{ t('AUTOMATION.ACTION.VARIABLES.AGENT_HINT') }}
    </p>
    <div class="flex flex-col gap-1">
      <p class="text-xs font-medium text-n-slate-11">
        {{ t('AUTOMATION.ACTION.VARIABLES.FILTERS_LABEL') }}
      </p>
      <div class="flex flex-wrap gap-1.5">
        <button
          v-for="snippet in AUTOMATION_LIQUID_FILTER_SNIPPETS"
          :key="snippet"
          type="button"
          class="text-xs px-2 py-1 rounded-md border border-n-weak text-n-slate-11 hover:bg-n-alpha-2 font-mono"
          @click="insertSnippet(snippet)"
        >
          {{ formatSnippetChip(snippet) }}
        </button>
      </div>
    </div>
    <div
      v-if="messagePreview"
      class="rounded-lg border border-n-weak bg-n-solid-1 p-2.5"
    >
      <p class="text-xs font-medium text-n-slate-11 mb-1">
        {{ t('AUTOMATION.ACTION.VARIABLES.PREVIEW_LABEL') }}
      </p>
      <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
        {{ messagePreview }}
      </p>
    </div>
  </div>
</template>
