<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import ConversationWorkflowRulesAPI from 'dashboard/api/conversationWorkflowRules';
import ConversationRuleRow from 'dashboard/routes/dashboard/settings/conversationRules/components/ConversationRuleRow.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  rules: {
    type: Array,
    default: () => [],
  },
  searchQuery: {
    type: String,
    default: '',
  },
  activeTab: {
    type: String,
    default: 'all',
  },
  isMigrated: {
    type: Boolean,
    default: false,
  },
  actionLoading: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['edit', 'clone', 'refresh']);

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const localRules = ref([]);
const showDeleteConfirmationPopup = ref(false);
const selectedRule = ref({});
const confirmDialog = ref(null);
const migrateConfirmDialog = ref(null);
const toggleModalTitle = ref('');
const toggleModalDescription = ref('');
const legacyAutoResolveActive = ref(false);
const isMigrating = ref(false);

const dragEnabled = computed(
  () =>
    props.activeTab === 'all' &&
    !props.searchQuery.trim() &&
    localRules.value.length > 1
);

const showLegacyBanner = computed(
  () => legacyAutoResolveActive.value && !props.isMigrated
);

const deleteMessage = computed(() => ` ${selectedRule.value.name}?`);

const noSearchResults = computed(
  () => props.searchQuery.trim() && !props.rules.length
);

watch(
  () => props.rules,
  value => {
    localRules.value = [...value];
    legacyAutoResolveActive.value =
      currentAccount.value?.auto_resolve_after > 0 && !props.isMigrated;
  },
  { immediate: true, deep: true }
);

const onReorderEnd = async () => {
  try {
    await ConversationWorkflowRulesAPI.reorder(
      localRules.value.map((rule, index) => ({ id: rule.id, position: index }))
    );
    emit('refresh');
  } catch {
    useAlert(t('CONVERSATION_RULES.REORDER_ERROR'));
    emit('refresh');
  }
};

const toggleActive = async rule => {
  try {
    if (rule.active) {
      toggleModalTitle.value = t('CONVERSATION_RULES.TOGGLE.DEACTIVATE_TITLE');
      toggleModalDescription.value = t(
        'CONVERSATION_RULES.TOGGLE.DEACTIVATE_DESCRIPTION',
        { ruleName: rule.name }
      );
    } else {
      toggleModalTitle.value = t('CONVERSATION_RULES.TOGGLE.ACTIVATE_TITLE');
      toggleModalDescription.value = t(
        'CONVERSATION_RULES.TOGGLE.ACTIVATE_DESCRIPTION',
        { ruleName: rule.name }
      );
    }

    const ok = await confirmDialog.value.showConfirmation();
    if (!ok) return;

    await ConversationWorkflowRulesAPI.update(rule.id, {
      active: !rule.active,
    });
    emit('refresh');
    useAlert(
      rule.active
        ? t('CONVERSATION_RULES.TOGGLE.DEACTIVATED')
        : t('CONVERSATION_RULES.TOGGLE.ACTIVATED')
    );
  } catch {
    useAlert(t('CONVERSATION_RULES.TOGGLE_ERROR'));
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
    emit('refresh');
    useAlert(t('CONVERSATION_RULES.DELETE_SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION_RULES.DELETE_ERROR'));
  }
};

const openMigrateConfirmation = async () => {
  const ok = await migrateConfirmDialog.value.showConfirmation();
  if (!ok) return;

  isMigrating.value = true;
  try {
    await ConversationWorkflowRulesAPI.migrateLegacy();
    await store.dispatch('accounts/get');
    emit('refresh');
    useAlert(t('CONVERSATION_RULES.MIGRATE_SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION_RULES.MIGRATE_ERROR'));
  } finally {
    isMigrating.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <p v-if="isMigrated" class="text-sm text-n-slate-11">
      {{ $t('CONVERSATION_RULES.MIGRATED_BANNER') }}
    </p>

    <div
      v-if="showLegacyBanner"
      class="flex flex-wrap items-center gap-2 p-3 rounded-lg border border-n-amber-6 bg-n-amber-2 text-sm text-n-amber-11"
    >
      <span>{{ $t('CONVERSATION_RULES.LEGACY_BANNER') }}</span>
      <Button
        link
        :label="$t('CONVERSATION_RULES.MIGRATE_NOW')"
        :is-loading="isMigrating"
        @click="openMigrateConfirmation"
      />
    </div>

    <p
      v-if="dragEnabled"
      class="text-xs text-n-slate-10 flex items-center gap-1.5"
    >
      <span class="i-lucide-grip-vertical size-3.5" />
      {{ $t('CONVERSATION_RULES.DRAG_HINT') }}
    </p>

    <p v-if="noSearchResults" class="py-10 text-center text-sm text-n-slate-11">
      {{ $t('CONVERSATION_RULES.NO_RESULTS') }}
    </p>

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
        <ConversationRuleRow
          :rule="rule"
          :loading="actionLoading[rule.id]"
          :drag-enabled="dragEnabled"
          @toggle="toggleActive"
          @edit="$emit('edit', $event)"
          @clone="$emit('clone', $event)"
          @delete="openDeletePopup"
        />
      </template>
    </Draggable>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('CONVERSATION_RULES.DELETE_CONFIRM_TITLE')"
      :message="$t('CONVERSATION_RULES.DELETE_CONFIRM')"
      :message-value="deleteMessage"
      :confirm-text="$t('CONVERSATION_RULES.DELETE_CONFIRM_YES')"
      :reject-text="$t('CONVERSATION_RULES.DELETE_CONFIRM_NO')"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="toggleModalTitle"
      :description="toggleModalDescription"
    />

    <woot-confirm-modal
      ref="migrateConfirmDialog"
      :title="$t('CONVERSATION_RULES.MIGRATE_CONFIRM.TITLE')"
      :description="$t('CONVERSATION_RULES.MIGRATE_CONFIRM.DESCRIPTION')"
      :confirm-label="$t('CONVERSATION_RULES.MIGRATE_CONFIRM.YES')"
      :cancel-label="$t('CONVERSATION_RULES.MIGRATE_CONFIRM.NO')"
    />
  </div>
</template>
