<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ConversationRequiredAttributes from 'dashboard/components-next/ConversationWorkflow/ConversationRequiredAttributes.vue';
import ConversationWorkflowRulesList from 'dashboard/components-next/ConversationWorkflow/ConversationWorkflowRulesList.vue';
import AutoResolve from 'dashboard/routes/dashboard/settings/account/components/AutoResolve.vue';

const { accountId, currentAccount } = useAccount();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isWorkflowMigrated = computed(
  () => !!currentAccount.value?.settings?.workflow_rules_migrated_at
);

const showWorkflowRules = computed(() => {
  return (
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS
    ) ||
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES
    )
  );
});

const showAutoResolutionConfig = computed(() => {
  return (
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS
    ) && !isWorkflowMigrated.value
  );
});

const showRequiredAttributes = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_REQUIRED_ATTRIBUTES
  );
});
</script>

<template>
  <SettingsLayout :no-records-found="false" class="gap-10">
    <template #header>
      <BaseSettingsHeader
        :title="$t('CONVERSATION_WORKFLOW.INDEX.HEADER.TITLE')"
        :description="$t('CONVERSATION_WORKFLOW.INDEX.HEADER.DESCRIPTION')"
        feature-name="conversation-workflow"
      />
    </template>

    <template #body>
      <div class="flex flex-col gap-6 mt-4">
        <ConversationWorkflowRulesList v-if="showWorkflowRules" />
        <p v-else class="text-sm text-n-slate-11">
          {{ $t('CONVERSATION_WORKFLOW.RULES.FEATURE_DISABLED') }}
        </p>
        <AutoResolve v-if="showAutoResolutionConfig" />
        <ConversationRequiredAttributes :is-enabled="showRequiredAttributes" />
      </div>
    </template>
  </SettingsLayout>
</template>
