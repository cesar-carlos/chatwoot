<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const { accountId } = useAccount();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasInactivity = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.AUTO_RESOLVE_CONVERSATIONS
  )
);

const hasAgentNoReply = computed(() =>
  isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.CONVERSATION_AGENT_NO_REPLY_RULES
  )
);
</script>

<template>
  <div
    class="flex flex-col gap-3 p-6 rounded-xl border border-n-weak bg-n-solid-2"
  >
    <div class="flex items-start gap-3">
      <span class="i-lucide-lock size-5 text-n-slate-10 flex-shrink-0 mt-0.5" />
      <div class="flex flex-col gap-2">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ $t('CONVERSATION_RULES.FEATURE_DISABLED_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ $t('CONVERSATION_RULES.FEATURE_DISABLED') }}
        </p>
        <ul class="text-sm text-n-slate-11 list-disc pl-5 space-y-1">
          <li :class="{ 'opacity-50': !hasInactivity }">
            {{ $t('CONVERSATION_RULES.TRIGGERS.conversation_inactivity') }}
            <span v-if="!hasInactivity" class="text-n-slate-10">
              {{ $t('CONVERSATION_RULES.FEATURE_DISABLED_SEPARATOR') }}
              {{ $t('CONVERSATION_RULES.FEATURE_DISABLED_UNAVAILABLE') }}
            </span>
          </li>
          <li :class="{ 'opacity-50': !hasAgentNoReply }">
            {{ $t('CONVERSATION_RULES.TRIGGERS.agent_no_reply') }}
            <span v-if="!hasAgentNoReply" class="text-n-slate-10">
              {{ $t('CONVERSATION_RULES.FEATURE_DISABLED_SEPARATOR') }}
              {{ $t('CONVERSATION_RULES.FEATURE_DISABLED_UNAVAILABLE') }}
            </span>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
