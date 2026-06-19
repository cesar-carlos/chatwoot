<script setup>
import {
  computed,
  h,
  nextTick,
  onMounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useOperators } from 'dashboard/components-next/filter/operators';
import { showActionInput } from 'dashboard/helper/automationHelper';
import ConversationWorkflowRulesAPI from 'dashboard/api/conversationWorkflowRules';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import { useWorkflowRule } from 'dashboard/composables/useWorkflowRule';
import {
  WORKFLOW_CONDITIONS,
  WORKFLOW_ACTION_TYPES,
  WORKFLOW_STATUS_OPTIONS,
} from 'dashboard/routes/dashboard/settings/conversationRules/constants';
import { inferDurationUnit } from 'dashboard/routes/dashboard/settings/conversationRules/helpers/durationHelper';
import { getTieredSlaExample } from 'dashboard/routes/dashboard/settings/conversationRules/helpers/i18nHelper';
import {
  getAvailableTriggers,
  getDurationLabelKey,
} from 'dashboard/routes/dashboard/settings/conversationRules/helpers/triggerHelper';
import FormSection from 'dashboard/routes/dashboard/settings/conversationRules/components/FormSection.vue';
import FormSwitchRow from 'dashboard/routes/dashboard/settings/conversationRules/components/FormSwitchRow.vue';
import TriggerCardSelector from 'dashboard/routes/dashboard/settings/conversationRules/components/TriggerCardSelector.vue';
import DurationPresets from 'dashboard/routes/dashboard/settings/conversationRules/components/DurationPresets.vue';
import ConditionRow from 'dashboard/components-next/filter/ConditionRow.vue';
import AutomationActionInput from 'dashboard/components/widgets/AutomationActionInput.vue';
import DurationInput from 'dashboard/components-next/input/DurationInput.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
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

const { t, tm } = useI18n();
const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const { operators } = useOperators();
const conditionsRef = useTemplateRef('conditionsRef');
const dialogRef = ref(null);
const unattendedCount = ref(null);
const previewCount = ref(null);
const isPreviewLoading = ref(false);
const durationUnit = ref(DURATION_UNITS.MINUTES);
const showTieredSlaExample = ref(false);

const {
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
} = useWorkflowRule(props.rule, props.existingRules);

const isEdit = computed(() => !!props.rule?.id);
const isConversationInactivity = computed(
  () => rule.value.trigger_type === 'conversation_inactivity'
);
const isAgentNoReply = computed(
  () => rule.value.trigger_type === 'agent_no_reply'
);
const isFirstResponseOverdue = computed(
  () => rule.value.trigger_type === 'first_response_overdue'
);
const showResponseScope = computed(
  () => isAgentNoReply.value || isFirstResponseOverdue.value
);
const showUnattendedLink = computed(
  () => isAgentNoReply.value || isFirstResponseOverdue.value
);

const durationLabelKey = computed(() =>
  getDurationLabelKey(rule.value.trigger_type)
);

const availableTriggers = computed(() =>
  getAvailableTriggers(isFeatureEnabledonAccount.value, accountId.value).map(
    item => ({
      key: item.key,
      icon: item.icon,
    })
  )
);

const tieredSlaExample = computed(() => getTieredSlaExample(tm));

const inboxOptions = computed(() =>
  (store.getters['inboxes/getInboxes'] || []).map(inbox => ({
    id: inbox.id,
    name: inbox.name,
  }))
);

const matchPreviewLabel = computed(() => {
  if (previewCount.value === null) return '';
  return t('CONVERSATION_RULES.FORM.MATCH_PREVIEW', {
    count: previewCount.value,
  });
});

const statusOptions = computed(() =>
  WORKFLOW_STATUS_OPTIONS.map(item => ({
    id: item.id,
    name: t(`CONVERSATION_RULES.STATUS.${item.id}`),
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
  get: () => rule.value.duration_minutes || 60,
  set: value => {
    rule.value.duration_minutes = value;
  },
});

const unattendedPreview = computed(() => {
  if (unattendedCount.value === null) return '';
  return t('CONVERSATION_RULES.FORM.UNATTENDED_PREVIEW', {
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

const fetchPreviewCount = async () => {
  if (!rule.value.duration_minutes || rule.value.duration_minutes < 10) {
    previewCount.value = null;
    return;
  }

  isPreviewLoading.value = true;
  try {
    const { data } = await ConversationWorkflowRulesAPI.previewCount(
      buildPayload()
    );
    previewCount.value = data?.count ?? 0;
  } catch {
    previewCount.value = null;
  } finally {
    isPreviewLoading.value = false;
  }
};

let previewTimeout;
const schedulePreviewCount = () => {
  clearTimeout(previewTimeout);
  previewTimeout = setTimeout(fetchPreviewCount, 400);
};

watch(
  () => rule.value.trigger_type,
  triggerType => {
    if (showUnattendedLink.value) {
      fetchUnattendedCount();
    }
    schedulePreviewCount();
  }
);

watch(
  () => [rule.value.duration_minutes, rule.value.inbox_ids, rule.value.options],
  () => schedulePreviewCount(),
  { deep: true }
);

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
    useAlert(t('CONVERSATION_RULES.SAVE_ERROR'));
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');

  if (!rule.value.duration_minutes || rule.value.duration_minutes < 10) {
    rule.value.duration_minutes = 60;
  }
  if (
    availableTriggers.value.length &&
    !availableTriggers.value.some(t => t.key === rule.value.trigger_type)
  ) {
    rule.value.trigger_type = availableTriggers.value[0].key;
  }
  durationUnit.value = inferDurationUnit(rule.value.duration_minutes);

  if (showUnattendedLink.value) {
    fetchUnattendedCount();
  }
  schedulePreviewCount();
  nextTick(() => {
    dialogRef.value?.open();
  });
});
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      isEdit ? $t('CONVERSATION_RULES.EDIT') : $t('CONVERSATION_RULES.ADD')
    "
    width="3xl"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="$emit('close')"
  >
    <div class="flex flex-col gap-4 max-h-[70vh] overflow-y-auto p-1">
      <FormSection
        :title="$t('CONVERSATION_RULES.FORM.SECTIONS.IDENTIFICATION')"
      >
        <NextInput
          v-model="rule.name"
          :label="$t('CONVERSATION_RULES.FORM.NAME')"
          :message="fieldErrors.name"
          :message-type="fieldErrors.name ? 'error' : 'info'"
        />
        <TextArea
          v-model="rule.description"
          :label="$t('CONVERSATION_RULES.FORM.DESCRIPTION')"
        />
      </FormSection>

      <FormSection
        :title="$t('CONVERSATION_RULES.FORM.SECTIONS.TRIGGER')"
        :description="$t('CONVERSATION_RULES.FORM.SECTIONS.TRIGGER_HELP')"
      >
        <TriggerCardSelector
          v-model="rule.trigger_type"
          :triggers="availableTriggers"
        />

        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium text-n-slate-12">
            {{ $t(durationLabelKey) }}
          </span>
          <DurationPresets v-model="rule.duration_minutes" />
          <div class="gap-2 w-full grid grid-cols-[3fr_1fr]">
            <DurationInput
              v-model="durationValue"
              v-model:unit="durationUnit"
              min="10"
              max="1438560"
              class="w-full"
            />
          </div>
          <span v-if="fieldErrors.duration" class="text-xs text-n-ruby-11">
            {{ fieldErrors.duration }}
          </span>
          <span
            v-else-if="matchPreviewLabel"
            class="text-xs text-n-slate-11"
            :class="{ 'opacity-60': isPreviewLoading }"
          >
            {{ matchPreviewLabel }}
          </span>
        </div>

        <div class="flex items-center gap-2">
          <Button
            link
            :label="
              showTieredSlaExample
                ? $t('CONVERSATION_RULES.FORM.HIDE_EXAMPLE')
                : $t('CONVERSATION_RULES.FORM.VIEW_EXAMPLE')
            "
            @click="showTieredSlaExample = !showTieredSlaExample"
          />
        </div>
        <ul
          v-if="showTieredSlaExample"
          class="text-sm text-n-slate-11 list-disc pl-5"
        >
          <li v-for="(item, index) in tieredSlaExample" :key="index">
            {{ item }}
          </li>
        </ul>
      </FormSection>

      <FormSection :title="$t('CONVERSATION_RULES.FORM.SECTIONS.SCOPE')">
        <MultiSelect
          v-model="rule.inbox_ids"
          :options="inboxOptions"
          :label="$t('CONVERSATION_RULES.FORM.INBOXES')"
          :placeholder="$t('CONVERSATION_RULES.FORM.ALL_INBOXES')"
        />

        <template v-if="isConversationInactivity">
          <FormSwitchRow
            v-model="rule.ignore_waiting"
            :label="$t('CONVERSATION_RULES.FORM.IGNORE_WAITING')"
            :help="$t('CONVERSATION_RULES.FORM.IGNORE_WAITING_HELP')"
          />
          <FormSwitchRow
            v-model="rule.resolve_on_match"
            :label="$t('CONVERSATION_RULES.FORM.RESOLVE_ON_MATCH')"
            :help="$t('CONVERSATION_RULES.FORM.RESOLVE_ON_MATCH_HELP')"
          />
          <TextArea
            v-model="rule.message"
            :label="$t('CONVERSATION_RULES.FORM.MESSAGE')"
          />
        </template>

        <template v-if="showResponseScope">
          <div v-if="showUnattendedLink" class="flex flex-col gap-1">
            <Button
              link
              :label="$t('CONVERSATION_RULES.FORM.UNATTENDED_LINK')"
              @click="goToUnattended"
            />
            <span v-if="unattendedPreview" class="text-sm text-n-slate-11">
              {{ unattendedPreview }}
            </span>
          </div>
          <MultiSelect
            v-model="rule.options.statuses"
            :options="statusOptions"
            :label="$t('CONVERSATION_RULES.FORM.STATUSES')"
          />
          <FormSwitchRow
            v-if="isAgentNoReply"
            v-model="rule.options.require_no_first_reply"
            :label="$t('CONVERSATION_RULES.FORM.REQUIRE_NO_FIRST_REPLY')"
            :help="$t('CONVERSATION_RULES.FORM.REQUIRE_NO_FIRST_REPLY_HELP')"
          />
        </template>

        <FormSwitchRow
          v-model="rule.options.respect_business_hours"
          :label="$t('CONVERSATION_RULES.FORM.RESPECT_BUSINESS_HOURS')"
          :help="$t('CONVERSATION_RULES.FORM.RESPECT_BUSINESS_HOURS_HELP')"
        />
      </FormSection>

      <FormSection :title="$t('CONVERSATION_RULES.FORM.SECTIONS.CONDITIONS')">
        <div class="flex items-center justify-end">
          <Button
            link
            :label="$t('CONVERSATION_RULES.FORM.ADD_CONDITION')"
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
        <span v-if="fieldErrors.conditions" class="text-xs text-n-ruby-11">
          {{ fieldErrors.conditions }}
        </span>
      </FormSection>

      <FormSection :title="$t('CONVERSATION_RULES.FORM.SECTIONS.ACTIONS')">
        <div class="flex items-center justify-end">
          <Button
            link
            :label="$t('CONVERSATION_RULES.FORM.ADD_ACTION')"
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
          <FormSwitchRow
            v-if="action.action_name === 'send_message'"
            v-model="action.counts_as_agent_reply"
            :label="$t('CONVERSATION_RULES.FORM.COUNTS_AS_AGENT_REPLY')"
            :help="$t('CONVERSATION_RULES.FORM.COUNTS_AS_AGENT_REPLY_HELP')"
          />
        </div>
        <span v-if="fieldErrors.actions" class="text-xs text-n-ruby-11">
          {{ fieldErrors.actions }}
        </span>
      </FormSection>
    </div>

    <template #footer>
      <Button
        faded
        slate
        :label="$t('CONVERSATION_RULES.FORM.CANCEL')"
        @click="$emit('close')"
      />
      <Button :label="$t('CONVERSATION_RULES.FORM.SAVE')" @click="saveRule" />
    </template>
  </Dialog>
</template>
