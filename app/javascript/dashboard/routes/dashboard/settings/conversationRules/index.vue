<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@scmmishra/pico-search';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import ConversationWorkflowRulesAPI from 'dashboard/api/conversationWorkflowRules';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConversationRulesList from './components/ConversationRulesList.vue';
import ConversationRuleForm from './components/ConversationRuleForm.vue';
import ConversationRulesEmptyState from './components/ConversationRulesEmptyState.vue';
import ConversationRulesFeatureDisabled from './components/ConversationRulesFeatureDisabled.vue';
import { WORKFLOW_TRIGGER_TABS } from './constants';
import { filterRulesByTab } from './helpers/triggerHelper';

const { t } = useI18n();
const store = useStore();
const { accountId, currentAccount } = useAccount();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const rules = ref([]);
const isLoading = ref(false);
const searchQuery = ref('');
const activeTriggerTab = ref('all');
const showForm = ref(false);
const editingRule = ref(null);
const actionLoading = ref({});

const hasInactivityFlag = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS
  )
);

const hasAgentNoReplyFlag = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES
  )
);

const showConversationRules = computed(
  () => hasInactivityFlag.value || hasAgentNoReplyFlag.value
);

const showPartialFeaturesBanner = computed(
  () =>
    showConversationRules.value &&
    hasInactivityFlag.value !== hasAgentNoReplyFlag.value
);

const triggerTabs = computed(() =>
  WORKFLOW_TRIGGER_TABS.map(tab => ({
    key: tab.key,
    label: t(tab.labelKey),
  }))
);

const tabFilteredRules = computed(() =>
  filterRulesByTab(rules.value, activeTriggerTab.value)
);

const filteredRules = computed(() => {
  const query = searchQuery.value.trim();
  const base = tabFilteredRules.value;
  if (!query) return base;
  return picoSearch(base, query, ['name', 'description']);
});

const hasSearchQuery = computed(() => !!searchQuery.value.trim());

const ruleCountLabel = computed(() => {
  if (!rules.value.length) return '';

  if (hasSearchQuery.value) {
    return t('CONVERSATION_RULES.COUNT_FILTERED', {
      filtered: filteredRules.value.length,
      total: tabFilteredRules.value.length,
    });
  }

  return t('CONVERSATION_RULES.COUNT', { n: tabFilteredRules.value.length });
});

const isMigrated = computed(
  () => !!currentAccount.value?.settings?.workflow_rules_migrated_at
);

const fetchRules = async () => {
  isLoading.value = true;
  try {
    const { data } = await ConversationWorkflowRulesAPI.get();
    rules.value = data;
  } catch {
    useAlert(t('CONVERSATION_RULES.FETCH_ERROR'));
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
  useAlert(t('CONVERSATION_RULES.SAVE_SUCCESS'));
};

const buildClonePayload = rule => {
  const {
    id: _id,
    created_at: _createdAt,
    updated_at: _updatedAt,
    legacy_auto_resolve_active: _legacy,
    ...rest
  } = rule;

  const maxPosition = rules.value.reduce(
    (max, item) => Math.max(max, item.position ?? 0),
    -1
  );

  return {
    ...rest,
    name: `${rule.name} ${t('CONVERSATION_RULES.CLONE.SUFFIX')}`,
    position: maxPosition + 1,
  };
};

const cloneRule = async rule => {
  actionLoading.value[rule.id] = true;
  try {
    await ConversationWorkflowRulesAPI.create(buildClonePayload(rule));
    await fetchRules();
    useAlert(t('CONVERSATION_RULES.CLONE.SUCCESS'));
  } catch {
    useAlert(t('CONVERSATION_RULES.CLONE.ERROR'));
  } finally {
    actionLoading.value[rule.id] = false;
  }
};

onMounted(() => {
  if (showConversationRules.value) {
    store.dispatch('inboxes/get');
    fetchRules();
  }
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading && showConversationRules"
    :loading-message="$t('CONVERSATION_RULES.LOADING')"
    :no-records-found="false"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('CONVERSATION_RULES.INDEX.HEADER.TITLE')"
        :description="$t('CONVERSATION_RULES.INDEX.HEADER.DESCRIPTION')"
        :search-placeholder="
          rules.length ? $t('CONVERSATION_RULES.SEARCH_PLACEHOLDER') : ''
        "
        feature-name="conversation_rules"
      >
        <template v-if="rules?.length" #tabs>
          <div class="flex items-center gap-1">
            <button
              v-for="tab in triggerTabs"
              :key="tab.key"
              type="button"
              class="px-2.5 py-1 rounded-md text-xs font-medium transition-colors"
              :class="
                activeTriggerTab === tab.key
                  ? 'bg-n-alpha-2 text-n-slate-12'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="activeTriggerTab = tab.key"
            >
              {{ tab.label }}
            </button>
          </div>
        </template>
        <template v-if="rules?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ ruleCountLabel }}
          </span>
        </template>
        <template v-if="showConversationRules" #actions>
          <Button
            :label="$t('CONVERSATION_RULES.ADD')"
            size="sm"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <ConversationRulesFeatureDisabled v-if="!showConversationRules" />

      <template v-else>
        <div
          v-if="showPartialFeaturesBanner"
          class="mb-4 p-3 rounded-lg border border-n-weak bg-n-solid-2 text-sm text-n-slate-11"
        >
          {{ $t('CONVERSATION_RULES.PARTIAL_FEATURES_BANNER') }}
        </div>

        <ConversationRulesEmptyState
          v-if="!isLoading && !rules.length"
          show-example
          @create="openCreate"
        />

        <p
          v-if="rules.length && !filteredRules.length && !hasSearchQuery"
          class="py-10 text-center text-sm text-n-slate-11"
        >
          {{ $t('CONVERSATION_RULES.NO_TAB_RESULTS') }}
        </p>

        <ConversationRulesList
          v-else-if="rules.length"
          :rules="filteredRules"
          :search-query="searchQuery"
          :is-migrated="isMigrated"
          :action-loading="actionLoading"
          @edit="openEdit"
          @clone="cloneRule"
          @refresh="fetchRules"
        />
      </template>
    </template>

    <ConversationRuleForm
      v-if="showForm"
      :rule="editingRule"
      :existing-rules="rules"
      @close="closeForm"
      @saved="handleSaved"
    />
  </SettingsLayout>
</template>
