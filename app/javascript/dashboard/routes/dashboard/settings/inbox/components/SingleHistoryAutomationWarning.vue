<script setup>
import { computed, toRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useSingleHistoryAutomationWarning } from 'dashboard/composables/fork/useSingleHistoryAutomationWarning';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  lockToSingleConversation: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const router = useRouter();

const { matchingRules, showAutomationWarning } =
  useSingleHistoryAutomationWarning(toRef(() => props.inboxId));

const isVisible = computed(
  () => props.lockToSingleConversation && showAutomationWarning.value
);

const warningMessage = computed(() => {
  const count = matchingRules.value.length;
  const ruleNames = matchingRules.value.map(rule => rule.name).join(', ');

  return t('INBOX_MGMT.EDIT.LOCK_TO_SINGLE_CONVERSATION.AUTOMATION_WARNING', {
    count,
    ruleNames,
  });
});

const goToAutomations = () => {
  router.push({ name: 'automation_list' });
};
</script>

<template>
  <div v-show="isVisible" class="mt-3 w-full">
    <Banner
      color="amber"
      :action-label="
        $t(
          'INBOX_MGMT.EDIT.LOCK_TO_SINGLE_CONVERSATION.AUTOMATION_WARNING_ACTION'
        )
      "
      class="w-full"
      @action="goToAutomations"
    >
      <div class="flex items-start gap-2">
        <Icon
          icon="i-lucide-triangle-alert"
          class="flex-shrink-0 size-4 mt-0.5"
        />
        <span>{{ warningMessage }}</span>
      </div>
    </Banner>
  </div>
</template>
