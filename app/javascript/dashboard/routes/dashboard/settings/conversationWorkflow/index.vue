<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ConversationRequiredAttributes from 'dashboard/components-next/ConversationWorkflow/ConversationRequiredAttributes.vue';
import AutoResolve from 'dashboard/routes/dashboard/settings/account/components/AutoResolve.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const router = useRouter();
const { accountId, currentAccount } = useAccount();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isWorkflowMigrated = computed(
  () => !!currentAccount.value?.settings?.workflow_rules_migrated_at
);

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

const goToConversationRules = () => {
  router.push({
    name: 'conversation_rules_index',
    params: { accountId: accountId.value },
  });
};
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
        <!-- FORK: migrated auto-resolve info card -->
        <div
          v-if="isWorkflowMigrated"
          class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-2"
        >
          <div class="flex flex-col gap-1">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION_RULES.CROSS_LINK.WORKFLOW_MIGRATED_TITLE') }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{
                $t(
                  'CONVERSATION_RULES.CROSS_LINK.WORKFLOW_MIGRATED_DESCRIPTION'
                )
              }}
            </p>
          </div>
          <Button
            :label="$t('CONVERSATION_RULES.CROSS_LINK.WORKFLOW_MIGRATED_LINK')"
            size="sm"
            @click="goToConversationRules"
          />
        </div>

        <AutoResolve v-if="showAutoResolutionConfig" />
        <ConversationRequiredAttributes :is-enabled="showRequiredAttributes" />
      </div>
    </template>
  </SettingsLayout>
</template>
