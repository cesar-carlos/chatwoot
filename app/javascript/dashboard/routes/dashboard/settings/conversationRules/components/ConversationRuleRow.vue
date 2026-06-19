<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { WORKFLOW_ACTION_TYPES } from 'dashboard/routes/dashboard/settings/conversationRules/constants';
import { formatWorkflowDuration } from '../helpers/durationHelper';

const props = defineProps({
  rule: {
    type: Object,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
  dragEnabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'edit', 'delete', 'clone']);

const { t } = useI18n();
const store = useStore();

const priorityLabel = computed(() =>
  t('CONVERSATION_RULES.PRIORITY', {
    position: (props.rule.position ?? 0) + 1,
  })
);

const durationLabel = computed(() =>
  formatWorkflowDuration(props.rule.duration_minutes, t)
);

const triggerLabel = computed(() =>
  t(`CONVERSATION_RULES.TRIGGERS.${props.rule.trigger_type}`)
);

const inboxSummary = computed(() => {
  const inboxIds = props.rule.inbox_ids;
  if (!inboxIds?.length) {
    return t('CONVERSATION_RULES.INBOX_SCOPE.ALL');
  }

  const inboxes = store.getters['inboxes/getInboxes'] || [];
  const names = inboxIds
    .map(id => inboxes.find(inbox => inbox.id === id)?.name)
    .filter(Boolean);

  if (names.length <= 2) return names.join(', ');
  return t('CONVERSATION_RULES.INBOX_SCOPE.COUNT', { count: names.length });
});

const actionSummary = computed(() => {
  const actions = props.rule.actions || [];
  if (!actions.length) {
    if (
      props.rule.trigger_type === 'conversation_inactivity' &&
      props.rule.resolve_on_match
    ) {
      return t('CONVERSATION_RULES.ACTION_SUMMARY.RESOLVE');
    }
    return '';
  }

  const getActionLabel = actionName => {
    const actionType = WORKFLOW_ACTION_TYPES.find(
      item => item.key === actionName
    );
    if (actionType) return t(`AUTOMATION.ACTIONS.${actionType.label}`);
    return actionName;
  };

  const labels = actions
    .slice(0, 2)
    .map(action => getActionLabel(action.action_name));

  if (actions.length > 2) {
    labels.push(
      t('CONVERSATION_RULES.ACTION_SUMMARY.MORE', {
        count: actions.length - 2,
      })
    );
  }

  return labels.join(', ');
});

const ruleActive = computed({
  get: () => props.rule.active,
  set: () => {
    emit('toggle', props.rule);
  },
});
</script>

<template>
  <div
    class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-weak transition-opacity"
    :class="{
      'opacity-60': !rule.active,
      'cursor-grab': dragEnabled,
    }"
  >
    <div class="flex items-center gap-3 min-w-0">
      <span
        v-if="dragEnabled"
        v-tooltip.top="$t('CONVERSATION_RULES.DRAG_HINT')"
        class="i-lucide-grip-vertical size-4 text-n-slate-10 flex-shrink-0"
        aria-hidden="true"
      />
      <span class="text-sm text-n-slate-11 flex-shrink-0 tabular-nums">
        {{ priorityLabel }}
      </span>
      <div class="flex flex-col gap-1 min-w-0">
        <div class="flex items-center gap-2 min-w-0">
          <span class="font-medium text-n-slate-12 truncate">{{
            rule.name
          }}</span>
          <span
            v-if="!rule.active"
            class="text-xs px-2 py-0.5 rounded-full bg-n-slate-3 text-n-slate-11 flex-shrink-0"
          >
            {{ $t('CONVERSATION_RULES.INACTIVE_BADGE') }}
          </span>
          <span
            v-else
            class="text-xs px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11 flex-shrink-0"
          >
            {{ $t('CONVERSATION_RULES.ACTIVE_BADGE') }}
          </span>
        </div>
        <span class="text-sm text-n-slate-11 truncate">
          {{ triggerLabel }}
          {{ $t('CONVERSATION_RULES.SEPARATOR') }}
          {{ durationLabel }}
          <template v-if="inboxSummary">
            {{ $t('CONVERSATION_RULES.SEPARATOR') }}
            {{ inboxSummary }}
          </template>
        </span>
        <span v-if="actionSummary" class="text-xs text-n-slate-10 truncate">
          {{ actionSummary }}
        </span>
      </div>
    </div>
    <div class="flex items-center gap-2 flex-shrink-0">
      <ToggleSwitch v-model="ruleActive" />
      <Button
        v-tooltip.top="$t('CONVERSATION_RULES.EDIT')"
        :aria-label="$t('CONVERSATION_RULES.EDIT')"
        icon="i-woot-edit-pen"
        slate
        sm
        :is-loading="loading"
        @click="$emit('edit', rule)"
      />
      <Button
        v-tooltip.top="$t('CONVERSATION_RULES.CLONE.TOOLTIP')"
        :aria-label="$t('CONVERSATION_RULES.CLONE.TOOLTIP')"
        icon="i-woot-clone"
        slate
        sm
        :is-loading="loading"
        @click="$emit('clone', rule)"
      />
      <Button
        v-tooltip.top="$t('CONVERSATION_RULES.DELETE_CONFIRM')"
        :aria-label="$t('CONVERSATION_RULES.DELETE_CONFIRM')"
        icon="i-woot-bin"
        slate
        sm
        class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
        :is-loading="loading"
        @click="$emit('delete', rule)"
      />
    </div>
  </div>
</template>
