<script setup>
import { computed, h, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { showActionInput } from 'dashboard/helper/automationHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ConversationWorkflowRulesAPI from 'dashboard/api/conversationWorkflowRules';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import { useWorkflowRule } from 'dashboard/composables/useWorkflowRule';
import {
  WORKFLOW_TRIGGERS,
  WORKFLOW_CONDITIONS,
  WORKFLOW_ACTION_TYPES,
  WORKFLOW_STATUS_OPTIONS,
} from 'dashboard/routes/dashboard/settings/conversationWorkflow/constants';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import AutomationActionInput from 'dashboard/components/widgets/AutomationActionInput.vue';
import DurationInput from 'dashboard/components-next/input/DurationInput.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import TextArea from 'next/textarea/TextArea.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { DURATION_UNITS } from 'dashboard/components-next/input/constants';

const props = defineProps({
  rule: {
    type: Object,
    default: null,
  },
  existingRules: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['close', 'saved']);

const INPUT_TYPE_MAP = {
  multi_select: 'multiSelect',
  search_select: 'searchSelect',
  plain_text: 'plainText',
  comma_separated_plain_text: 'plainText',
  date: 'date',
};

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const { operators } = useOperators();
const conditionsRef = useTemplateRef('conditionsRef');
const unattendedCount = ref(null);

const {
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
} = useWorkflowRule(props.rule, props.existingRules);

const isEdit = computed(() => !!props.rule?.id);
const isInactivity = computed(
  () => rule.value.trigger_type === 'conversation_inactivity'
);
const isAgentNoReply = computed(
  () => rule.value.trigger_type === 'agent_no_reply'
);

const tieredSlaExample = computed(() =>
  t('CONVERSATION_WORKFLOW.RULES.FORM.TIERED_SLA_EXAMPLE', {
    returnObjects: true,
  })
);

const inboxOptions = computed(() =>
  (store.getters['inboxes/getInboxes'] || []).map(inbox => ({
    id: inbox.id,
    name: inbox.name,
  }))
);

const triggerOptions = computed(() =>
  WORKFLOW_TRIGGERS.filter(trigger => {
    if (trigger.key === 'conversation_inactivity') {
      return isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS
      );
    }
    if (trigger.key === 'agent_no_reply') {
      return isFeatureEnabledonAccount.value(
        accountId.value,
        FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES
      );
    }
    return true;
  }).map(item => ({
    id: item.key,
    name: t(`CONVERSATION_WORKFLOW.RULES.TRIGGERS.${item.key}`),
  }))
);

const statusOptions = computed(() =>
  WORKFLOW_STATUS_OPTIONS.map(item => ({
    id: item.id,
    name: t(`CONVERSATION_WORKFLOW.RULES.STATUS.${item.id}`),
  }))
);

const workflowFilterTypes = computed(() =>
  WORKFLOW_CONDITIONS.map(attr => {
    const mappedInputType = INPUT_TYPE_MAP[attr.inputType] || 'plainText';
    const options = getWorkflowConditionDropdownValues(attr.key) || [];

    const filterOperators = (attr.filterOperators || []).map(op => {
      const enriched = operators.value[op.value];
      if (enriched) return enriched;
      return {
        value: op.value,
        label: t(`FILTER.OPERATOR_LABELS.${op.value}`),
        hasInput: true,
        inputOverride: null,
        icon: h('span', { class: 'i-ph-equals-bold !text-n-blue-11' }),
      };
    });

    return {
      attributeKey: attr.key,
      value: attr.key,
      attributeName: t(`AUTOMATION.ATTRIBUTES.${attr.name}`),
      label: t(`AUTOMATION.ATTRIBUTES.${attr.name}`),
      inputType: mappedInputType,
      options,
      filterOperators,
      dataType: 'text',
      attributeModel: 'standard',
    };
  })
);

const workflowActionTypes = computed(() =>
  WORKFLOW_ACTION_TYPES.map(action => ({
    ...action,
    label: t(`AUTOMATION.ACTIONS.${action.label}`),
  }))
);

const durationValue = computed({
  get: () => rule.value.duration_minutes || 0,
  set: value => {
    rule.value.duration_minutes = value;
  },
});

const unattendedPreview = computed(() => {
  if (unattendedCount.value === null) return '';
  return t('CONVERSATION_WORKFLOW.RULES.FORM.UNATTENDED_PREVIEW', {
    count: unattendedCount.value,
  });
});

const goToUnattended = () => {
  router.push({
    name: 'conversation_unattended',
    params: { accountId: accountId.value },
  });
};

const fetchUnattendedCount = async () => {
  try {
    const { data } = await ConversationAPI.meta({ assigneeType: 'unattended' });
    unattendedCount.value = data?.meta?.all_count ?? 0;
  } catch {
    unattendedCount.value = null;
  }
};

const saveRule = async () => {
  if (!validateRule()) return;

  if (conditionsRef.value?.length) {
    const allValid = conditionsRef.value.every(condition =>
      condition.validate()
    );
    if (!allValid) return;
  }

  try {
    const payload = buildPayload();
    if (isEdit.value) {
      await ConversationWorkflowRulesAPI.update(props.rule.id, payload);
    } else {
      await ConversationWorkflowRulesAPI.create(payload);
    }
    emit('saved');
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.RULES.SAVE_ERROR'));
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  if (isAgentNoReply.value) {
    fetchUnattendedCount();
  }
});
</script>

<template>
  <Dialog
    :title="
      isEdit
        ? $t('CONVERSATION_WORKFLOW.RULES.EDIT')
        : $t('CONVERSATION_WORKFLOW.RULES.ADD')
    "
    width="3xl"
    @close="$emit('close')"
  >
    <div class="flex flex-col gap-4 max-h-[70vh] overflow-y-auto p-1">
      <NextInput
        v-model="rule.name"
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.NAME')"
      />
      <TextArea
        v-model="rule.description"
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.DESCRIPTION')"
      />

      <SingleSelect
        v-model="rule.trigger_type"
        :options="triggerOptions"
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.TRIGGER')"
      />

      <DurationInput
        v-model="durationValue"
        v-model:unit="DURATION_UNITS.MINUTES"
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.DURATION')"
      />

      <MultiSelect
        v-model="rule.inbox_ids"
        :options="inboxOptions"
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.INBOXES')"
        :placeholder="$t('CONVERSATION_WORKFLOW.RULES.FORM.ALL_INBOXES')"
      />

      <template v-if="isInactivity">
        <Switch
          v-model="rule.ignore_waiting"
          :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.IGNORE_WAITING')"
        />
        <Switch
          v-model="rule.resolve_on_match"
          :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.RESOLVE_ON_MATCH')"
        />
        <TextArea
          v-model="rule.message"
          :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.MESSAGE')"
        />
      </template>

      <template v-if="isAgentNoReply">
        <div class="flex flex-col gap-1">
          <Button
            link
            :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.UNATTENDED_LINK')"
            @click="goToUnattended"
          />
          <span v-if="unattendedPreview" class="text-sm text-n-slate-11">
            {{ unattendedPreview }}
          </span>
        </div>
        <MultiSelect
          v-model="rule.options.statuses"
          :options="statusOptions"
          :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.STATUSES')"
        />
        <Switch
          v-model="rule.options.require_no_first_reply"
          :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.REQUIRE_NO_FIRST_REPLY')"
        />
      </template>

      <Switch
        v-model="rule.options.respect_business_hours"
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.RESPECT_BUSINESS_HOURS')"
      />

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('CONVERSATION_WORKFLOW.RULES.FORM.TIERED_SLA_TITLE') }}
        </span>
        <ul class="text-sm text-n-slate-11 list-disc pl-5">
          <li v-for="(item, index) in tieredSlaExample" :key="index">
            {{ item }}
          </li>
        </ul>
      </div>

      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('CONVERSATION_WORKFLOW.RULES.FORM.CONDITIONS') }}
          </span>
          <Button
            link
            :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.ADD_CONDITION')"
            @click="appendNewCondition"
          />
        </div>
        <template v-for="(condition, index) in rule.conditions" :key="index">
          <ConditionRow
            v-if="index === 0"
            ref="conditionsRef"
            v-model:attribute-key="rule.conditions[index].attribute_key"
            v-model:filter-operator="rule.conditions[index].filter_operator"
            v-model:values="rule.conditions[index].values"
            :filter-types="workflowFilterTypes"
            :show-query-operator="false"
            @remove="removeCondition(index)"
          />
          <ConditionRow
            v-else
            ref="conditionsRef"
            v-model:attribute-key="rule.conditions[index].attribute_key"
            v-model:filter-operator="rule.conditions[index].filter_operator"
            v-model:query-operator="rule.conditions[index - 1].query_operator"
            v-model:values="rule.conditions[index].values"
            :filter-types="workflowFilterTypes"
            show-query-operator
            @remove="removeCondition(index)"
          />
        </template>
      </div>

      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t('CONVERSATION_WORKFLOW.RULES.FORM.ACTIONS') }}
          </span>
          <Button
            link
            :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.ADD_ACTION')"
            @click="appendNewAction"
          />
        </div>
        <div
          v-for="(action, index) in rule.actions"
          :key="index"
          class="flex flex-col gap-2"
        >
          <AutomationActionInput
            v-model="rule.actions[index]"
            :action-types="workflowActionTypes"
            :dropdown-values="getActionDropdownValues(action.action_name)"
            :show-action-input="
              showActionInput(workflowActionTypes, action.action_name)
            "
            @reset-action="resetAction(index)"
            @remove-action="removeAction(index)"
          />
          <Switch
            v-if="action.action_name === 'send_message'"
            v-model="action.counts_as_agent_reply"
            :label="
              $t('CONVERSATION_WORKFLOW.RULES.FORM.COUNTS_AS_AGENT_REPLY')
            "
          />
        </div>
      </div>
    </div>

    <template #footer>
      <Button
        faded
        slate
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.CANCEL')"
        @click="$emit('close')"
      />
      <Button
        :label="$t('CONVERSATION_WORKFLOW.RULES.FORM.SAVE')"
        @click="saveRule"
      />
    </template>
  </Dialog>
</template>
