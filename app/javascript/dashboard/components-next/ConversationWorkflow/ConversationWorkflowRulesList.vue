<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import ConversationWorkflowRulesAPI from 'dashboard/api/conversationWorkflowRules';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import ConversationWorkflowRuleForm from './ConversationWorkflowRuleForm.vue';

const { t } = useI18n();
const { currentAccount } = useAccount();

const rules = ref([]);
const localRules = ref([]);
const isLoading = ref(false);
const showForm = ref(false);
const editingRule = ref(null);
const showDeleteConfirmationPopup = ref(false);
const selectedRule = ref({});
const confirmDialog = ref(null);
const toggleModalTitle = ref('');
const toggleModalDescription = ref('');
const legacyAutoResolveActive = ref(false);
const isMigrating = ref(false);

const isMigrated = computed(
  () => !!currentAccount.value?.settings?.workflow_rules_migrated_at
);

const showLegacyBanner = computed(
  () => legacyAutoResolveActive.value && !isMigrated.value
);

const dragEnabled = computed(() => localRules.value.length > 1);

const deleteMessage = computed(() => ` ${selectedRule.value.name}?`);

watch(
  rules,
  value => {
    localRules.value = [...value];
  },
  { immediate: true, deep: true }
);

const fetchRules = async () => {
  isLoading.value = true;
  try {
    const { data } = await ConversationWorkflowRulesAPI.get();
    rules.value = data;
    legacyAutoResolveActive.value =
      currentAccount.value?.auto_resolve_after > 0 && !isMigrated.value;
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.RULES.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  editingRule.value = null;
  showForm.value = true;
};

const openEdit = rule => {
  editingRule.value = { ...rule };
  showForm.value = true;
};

const closeForm = () => {
  showForm.value = false;
  editingRule.value = null;
};

const handleSaved = async () => {
  closeForm();
  await fetchRules();
  useAlert(t('CONVERSATION_WORKFLOW.RULES.SAVE_SUCCESS'));
};

const onReorderEnd = async () => {
  try {
    await ConversationWorkflowRulesAPI.reorder(
      localRules.value.map((rule, index) => ({ id: rule.id, position: index }))
    );
    rules.value = [...localRules.value];
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.RULES.REORDER_ERROR'));
    await fetchRules();
  }
};

const toggleActive = async rule => {
  try {
    if (rule.active) {
      toggleModalTitle.value = t(
        'CONVERSATION_WORKFLOW.RULES.TOGGLE.DEACTIVATE_TITLE'
      );
      toggleModalDescription.value = t(
        'CONVERSATION_WORKFLOW.RULES.TOGGLE.DEACTIVATE_DESCRIPTION',
        { ruleName: rule.name }
      );
    } else {
      toggleModalTitle.value = t(
        'CONVERSATION_WORKFLOW.RULES.TOGGLE.ACTIVATE_TITLE'
      );
      toggleModalDescription.value = t(
        'CONVERSATION_WORKFLOW.RULES.TOGGLE.ACTIVATE_DESCRIPTION',
        { ruleName: rule.name }
      );
    }

    const ok = await confirmDialog.value.showConfirmation();
    if (!ok) return;

    await ConversationWorkflowRulesAPI.update(rule.id, {
      active: !rule.active,
    });
    await fetchRules();
    useAlert(
      rule.active
        ? t('CONVERSATION_WORKFLOW.RULES.TOGGLE.DEACTIVATED')
        : t('CONVERSATION_WORKFLOW.RULES.TOGGLE.ACTIVATED')
    );
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.RULES.TOGGLE_ERROR'));
  }
};

const openDeletePopup = rule => {
  selectedRule.value = rule;
  showDeleteConfirmationPopup.value = true;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const confirmDeletion = async () => {
  closeDeletePopup();
  try {
    await ConversationWorkflowRulesAPI.delete(selectedRule.value.id);
    await fetchRules();
    useAlert(t('CONVERSATION_WORKFLOW.RULES.DELETE_SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.RULES.DELETE_ERROR'));
  }
};

const migrateLegacy = async () => {
  isMigrating.value = true;
  try {
    await ConversationWorkflowRulesAPI.migrateLegacy();
    await fetchRules();
    useAlert(t('CONVERSATION_WORKFLOW.RULES.MIGRATE_SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION_WORKFLOW.RULES.MIGRATE_ERROR'));
  } finally {
    isMigrating.value = false;
  }
};

onMounted(fetchRules);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex items-center justify-between gap-4">
      <div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ $t('CONVERSATION_WORKFLOW.RULES.TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ $t('CONVERSATION_WORKFLOW.RULES.DESCRIPTION') }}
        </p>
        <p v-if="isMigrated" class="text-sm text-n-slate-11 mt-1">
          {{ $t('CONVERSATION_WORKFLOW.RULES.MIGRATED_BANNER') }}
        </p>
        <div
          v-if="showLegacyBanner"
          class="flex flex-wrap items-center gap-2 mt-2 text-sm text-n-amber-11"
        >
          <span>{{ $t('CONVERSATION_WORKFLOW.RULES.LEGACY_BANNER') }}</span>
          <Button
            link
            :label="$t('CONVERSATION_WORKFLOW.RULES.MIGRATE_NOW')"
            :is-loading="isMigrating"
            @click="migrateLegacy"
          />
        </div>
      </div>
      <Button
        :label="$t('CONVERSATION_WORKFLOW.RULES.ADD')"
        @click="openCreate"
      />
    </div>

    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ $t('CONVERSATION_WORKFLOW.RULES.LOADING') }}
    </div>

    <div v-else-if="!rules.length" class="text-sm text-n-slate-11">
      {{ $t('CONVERSATION_WORKFLOW.RULES.EMPTY') }}
    </div>

    <Draggable
      v-else
      v-model="localRules"
      :disabled="!dragEnabled"
      item-key="id"
      tag="div"
      class="flex flex-col gap-2"
      @end="onReorderEnd"
    >
      <template #item="{ element: rule }">
        <div
          class="flex items-center justify-between gap-4 p-4 rounded-xl border border-n-weak"
          :class="{ 'cursor-grab': dragEnabled }"
        >
          <div class="flex items-center gap-3 min-w-0">
            <span class="text-sm text-n-slate-11 flex-shrink-0">
              {{ $t('CONVERSATION_WORKFLOW.RULES.POSITION', { position: rule.position }) }}
            </span>
            <div class="flex flex-col gap-1 min-w-0">
              <span class="font-medium text-n-slate-12 truncate">{{
                rule.name
              }}</span>
              <span class="text-sm text-n-slate-11 truncate">
                {{
                  $t(
                    `CONVERSATION_WORKFLOW.RULES.TRIGGERS.${rule.trigger_type}`
                  )
                }}
                {{ $t('CONVERSATION_WORKFLOW.RULES.SEPARATOR') }}
                {{ rule.duration_minutes }}
                {{ $t('CONVERSATION_WORKFLOW.RULES.MINUTES') }}
              </span>
            </div>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0">
            <ToggleSwitch
              :model-value="rule.active"
              @update:model-value="toggleActive(rule)"
            />
            <Button icon="i-woot-edit-pen" slate sm @click="openEdit(rule)" />
            <Button icon="i-woot-bin" slate sm @click="openDeletePopup(rule)" />
          </div>
        </div>
      </template>
    </Draggable>

    <ConversationWorkflowRuleForm
      v-if="showForm"
      :rule="editingRule"
      :existing-rules="rules"
      @close="closeForm"
      @saved="handleSaved"
    />

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('CONVERSATION_WORKFLOW.RULES.DELETE_CONFIRM_TITLE')"
      :message="$t('CONVERSATION_WORKFLOW.RULES.DELETE_CONFIRM')"
      :message-value="deleteMessage"
      :confirm-text="$t('CONVERSATION_WORKFLOW.RULES.DELETE_CONFIRM_YES')"
      :reject-text="$t('CONVERSATION_WORKFLOW.RULES.DELETE_CONFIRM_NO')"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="toggleModalTitle"
      :description="toggleModalDescription"
    />
  </div>
</template>
