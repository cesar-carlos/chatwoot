<script setup>
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import SingleHistoryAutomationWarning from './SingleHistoryAutomationWarning.vue'; // FORK: single-history automation warning

defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  lockToSingleConversation: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['update']);
</script>

<template>
  <div class="flex flex-col w-full min-w-0">
    <div
      class="flex flex-col sm:flex-row flex-col items-start gap-4 mt-3 min-w-0"
    >
      <RadioCard
        id="disabled"
        :label="$t('INBOX_MGMT.EDIT.LOCK_TO_SINGLE_CONVERSATION.DISABLED')"
        :description="
          $t('INBOX_MGMT.EDIT.LOCK_TO_SINGLE_CONVERSATION.DISABLED_DESCRIPTION')
        "
        :is-active="!lockToSingleConversation"
        class="flex-1"
        @select="$emit('update', false)"
      />

      <RadioCard
        id="enabled"
        :label="$t('INBOX_MGMT.EDIT.LOCK_TO_SINGLE_CONVERSATION.ENABLED')"
        :description="
          $t('INBOX_MGMT.EDIT.LOCK_TO_SINGLE_CONVERSATION.ENABLED_DESCRIPTION')
        "
        :is-active="lockToSingleConversation"
        class="flex-1"
        @select="$emit('update', true)"
      />
    </div>
    <SingleHistoryAutomationWarning
      :inbox-id="inboxId"
      :lock-to-single-conversation="lockToSingleConversation"
    />
  </div>
</template>
