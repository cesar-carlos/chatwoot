<script setup>
import {
  computed,
  h,
  nextTick,
  onMounted,
  onUnmounted,
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
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
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
const panelRef = ref(null);
const confirmDialogRef = ref(null);
const actionsSectionRef = ref(null);
const unattendedCount = ref(null);
const previewCount = ref(null);
const isPreviewLoading = ref(false);
const durationUnit = ref(DURATION_UNITS.MINUTES);
const showTieredSlaExample = ref(false);
const showActivity = ref(false);
const activityLoading = ref(false);
const activity = ref({ executions: [], skips: [] });
const pendingSave = ref(false);

const {
  rule,
  fieldErrors,
  appendNewCondition,
  appendNewAction: appendNewActionBase,
  removeCondition,
  removeAction,
  resetAction: resetActionBase,
  getWorkflowConditionDropdownValues,
  getActionDropdownValues,
  validateRule,
  buildPayload,
  hydrateRuleForForm,
} = useWorkflowRule(props.rule, props.existingRules);

const hasContactMessageAction = computed(() =>
  (rule.value.actions || []).some(
    action => action.action_name === 'send_message_to_contact'
  )
);

const conditionsDefaultOpen = computed(() => !hasContactMessageAction.value);

const scrollToContactMessage = () => {
  nextTick(() => {
    nextTick(() => {
      const target =
        actionsSectionRef.value?.querySelector('[data-contact-message-block]') ||
        actionsSectionRef.value;
      target?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    });
  });
};

const appendNewAction = () => {
  appendNewActionBase();
  scrollToContactMessage();
};

const resetAction = index => {
  resetActionBase(index);
  if (rule.value.actions[index]?.action_name === 'send_message_to_contact') {
    scrollToContactMessage();
  }
};

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

const workflowActionTypes = computed(() => {
  const actions =
    rule.value.trigger_type === 'conversation_inactivity'
      ? WORKFLOW_ACTION_TYPES.filter(
          action => action.key !== 'resolve_conversation'
        )
      : WORKFLOW_ACTION_TYPES;

  return actions.map(action => ({
    ...action,
    label: t(`AUTOMATION.ACTIONS.${action.label}`),
  }));
});

const triggerUnavailable = computed(
  () =>
    !!rule.value.trigger_type &&
    availableTriggers.value.length > 0 &&
    !availableTriggers.value.some(
      trigger => trigger.key === rule.value.trigger_type
    )
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

const contactMessageConfirmSummary = computed(() => {
  const action = (rule.value.actions || []).find(
    item => item.action_name === 'send_message_to_contact'
  );
  if (!action) return '';

  const [inboxId, contactValue, message] = action.action_params || [];
  const inbox = (store.getters['inboxes/getInboxes'] || []).find(
    item => item.id === Number(inboxId)
  );
  const contactLabel =
    (contactValue && typeof contactValue === 'object' && contactValue.name) ||
    (contactValue?.id ? `#${contactValue.id}` : contactValue ? `#${contactValue}` : '—');
  const preview = String(message || '')
    .replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, key) => {
      const sample = {
        'conversation.display_id': '1234',
        'contact.name': 'João',
        'inbox.name': inbox?.name || 'Inbox',
        'rule.name': rule.value.name || 'Rule',
      };
      return sample[key] || `{{${key}}}`;
    })
    .slice(0, 160);

  return t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONFIRM_SUMMARY', {
    inbox: inbox?.name || `#${inboxId}`,
    contact: contactLabel,
    preview: preview || '—',
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
    const { data } =
      await ConversationWorkflowRulesAPI.previewCount(buildPayload());
    previewCount.value = data?.count ?? 0;
  } catch {
    previewCount.value = null;
  } finally {
    isPreviewLoading.value = false;
  }
};

const fetchActivity = async () => {
  if (!isEdit.value || !props.rule?.id) return;
  activityLoading.value = true;
  try {
    const { data } = await ConversationWorkflowRulesAPI.activity(props.rule.id);
    activity.value = {
      executions: data?.executions || [],
      skips: data?.skips || [],
    };
  } catch {
    activity.value = { executions: [], skips: [] };
  } finally {
    activityLoading.value = false;
  }
};

let previewTimeout;
const schedulePreviewCount = () => {
  clearTimeout(previewTimeout);
  previewTimeout = setTimeout(fetchPreviewCount, 400);
};

onUnmounted(() => clearTimeout(previewTimeout));

watch(
  () => rule.value.trigger_type,
  () => {
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

watch(
  () => rule.value.actions?.map(action => action.action_name).join(','),
  () => {
    if (hasContactMessageAction.value) scrollToContactMessage();
  }
);

const persistRule = async () => {
  try {
    const payload = buildPayload();
    let response;
    if (isEdit.value) {
      response = await ConversationWorkflowRulesAPI.update(
        props.rule.id,
        payload
      );
    } else {
      response = await ConversationWorkflowRulesAPI.create(payload);
    }
    if (response?.data?.legacy_auto_resolve_active) {
      useAlert(t('CONVERSATION_RULES.LEGACY_BANNER'));
    }
    emit('saved');
  } catch (error) {
    const payload = error?.response?.data?.error;
    const legacyConflict =
      (typeof payload === 'object' &&
        Array.isArray(payload?.base) &&
        payload.base.some(msg =>
          String(msg).toLowerCase().includes('migrate legacy')
        )) ||
      String(payload || '')
        .toLowerCase()
        .includes('migrate legacy');
    useAlert(
      legacyConflict
        ? t('CONVERSATION_RULES.LEGACY_CONFLICT')
        : t('CONVERSATION_RULES.SAVE_ERROR')
    );
  } finally {
    pendingSave.value = false;
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

  if (hasContactMessageAction.value) {
    pendingSave.value = true;
    nextTick(() => confirmDialogRef.value?.open());
    return;
  }

  await persistRule();
};

const onConfirmSave = async () => {
  confirmDialogRef.value?.close();
  await persistRule();
};

const onCancelConfirm = () => {
  pendingSave.value = false;
  confirmDialogRef.value?.close();
};

const closePanel = () => {
  panelRef.value?.close();
  emit('close');
};

const formatActivityTime = value => {
  if (!value) return '';
  try {
    return new Date(value).toLocaleString();
  } catch {
    return value;
  }
};

onMounted(async () => {
  await Promise.all([
    store.dispatch('inboxes/get'),
    store.dispatch('agents/get'),
    store.dispatch('teams/get'),
    store.dispatch('labels/get'),
  ]);

  hydrateRuleForForm({
    inboxOptions: inboxOptions.value,
    statusLabelFn: statusId => t(`CONVERSATION_RULES.STATUS.${statusId}`),
  });

  if (!rule.value.duration_minutes || rule.value.duration_minutes < 10) {
    rule.value.duration_minutes = 60;
  }
  durationUnit.value = inferDurationUnit(rule.value.duration_minutes);

  if (showUnattendedLink.value) {
    fetchUnattendedCount();
  }
  schedulePreviewCount();
  if (isEdit.value) fetchActivity();

  nextTick(() => {
    panelRef.value?.open();
    if (hasContactMessageAction.value) scrollToContactMessage();
  });
});
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="3xl"
    :title="
      isEdit ? $t('CONVERSATION_RULES.EDIT') : $t('CONVERSATION_RULES.ADD')
    "
    @close="$emit('close')"
  >
    <div class="flex flex-col gap-4">
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
        <p
          v-if="triggerUnavailable"
          class="text-sm text-n-amber-11 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3"
        >
          {{ $t('CONVERSATION_RULES.FORM.TRIGGER_UNAVAILABLE') }}
        </p>

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

      <FormSection
        :title="$t('CONVERSATION_RULES.FORM.SECTIONS.CONDITIONS')"
        collapsible
        :default-open="conditionsDefaultOpen"
      >
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

      <div ref="actionsSectionRef">
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
            :key="`${index}-${action.action_name}`"
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
              v-model="rule.actions[index].counts_as_agent_reply"
              :label="$t('CONVERSATION_RULES.FORM.COUNTS_AS_AGENT_REPLY')"
              :help="$t('CONVERSATION_RULES.FORM.COUNTS_AS_AGENT_REPLY_HELP')"
            />
          </div>
          <span v-if="fieldErrors.actions" class="text-xs text-n-ruby-11">
            {{ fieldErrors.actions }}
          </span>
        </FormSection>
      </div>

      <FormSection
        v-if="isEdit"
        :title="$t('CONVERSATION_RULES.FORM.SECTIONS.ACTIVITY')"
        collapsible
        :default-open="false"
      >
        <div class="flex items-center justify-between gap-2">
          <p class="text-sm text-n-slate-11">
            {{ $t('CONVERSATION_RULES.FORM.ACTIVITY.DESCRIPTION') }}
          </p>
          <Button
            link
            :label="
              showActivity
                ? $t('CONVERSATION_RULES.FORM.ACTIVITY.HIDE')
                : $t('CONVERSATION_RULES.FORM.ACTIVITY.SHOW')
            "
            @click="
              showActivity = !showActivity;
              if (showActivity) fetchActivity();
            "
          />
        </div>
        <div v-if="showActivity" class="flex flex-col gap-3">
          <p v-if="activityLoading" class="text-sm text-n-slate-11">
            {{ $t('CONVERSATION_RULES.FORM.ACTIVITY.LOADING') }}
          </p>
          <template v-else>
            <div>
              <p class="text-xs font-medium text-n-slate-11 mb-1">
                {{ $t('CONVERSATION_RULES.FORM.ACTIVITY.EXECUTIONS') }}
              </p>
              <p
                v-if="!activity.executions.length"
                class="text-sm text-n-slate-10"
              >
                {{ $t('CONVERSATION_RULES.FORM.ACTIVITY.EMPTY_EXECUTIONS') }}
              </p>
              <ul v-else class="flex flex-col gap-1">
                <li
                  v-for="item in activity.executions"
                  :key="`exec-${item.id}`"
                  class="text-sm text-n-slate-12"
                >
                  #{{ item.display_id || item.conversation_id }}
                  ·
                  {{ formatActivityTime(item.executed_at) }}
                </li>
              </ul>
            </div>
            <div>
              <p class="text-xs font-medium text-n-slate-11 mb-1">
                {{ $t('CONVERSATION_RULES.FORM.ACTIVITY.SKIPS') }}
              </p>
              <p
                v-if="!activity.skips.length"
                class="text-sm text-n-slate-10"
              >
                {{ $t('CONVERSATION_RULES.FORM.ACTIVITY.EMPTY_SKIPS') }}
              </p>
              <ul v-else class="flex flex-col gap-1">
                <li
                  v-for="item in activity.skips"
                  :key="`skip-${item.id}`"
                  class="text-sm text-n-slate-12"
                >
                  {{ item.action_name }} · {{ item.reason }} ·
                  {{ formatActivityTime(item.created_at) }}
                </li>
              </ul>
            </div>
          </template>
        </div>
      </FormSection>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          faded
          slate
          class="w-full"
          :label="$t('CONVERSATION_RULES.FORM.CANCEL')"
          @click="closePanel"
        />
        <Button
          class="w-full"
          :label="$t('CONVERSATION_RULES.FORM.SAVE')"
          :is-loading="pendingSave"
          @click="saveRule"
        />
      </div>
    </template>
  </SidePanel>

  <Dialog
    ref="confirmDialogRef"
    type="edit"
    :title="$t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONFIRM_TITLE')"
    :description="contactMessageConfirmSummary"
    :confirm-button-label="
      $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONFIRM_YES')
    "
    :cancel-button-label="
      $t('CONVERSATION_RULES.FORM.CONTACT_MESSAGE.CONFIRM_NO')
    "
    @confirm="onConfirmSave"
    @close="onCancelConfirm"
  />
</template>
