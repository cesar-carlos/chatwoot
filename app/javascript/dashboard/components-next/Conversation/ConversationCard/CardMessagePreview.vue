<script setup>
import { computed } from 'vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MessagePreview from './MessagePreview.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  unreadCount: {
    type: Number,
    default: 0,
  },
});

const lastNonActivityMessage = computed(() =>
  useSnakeCase(props.conversation.lastNonActivityMessage ?? {}, { deep: true })
);

const assignee = computed(() => {
  const { meta: { assignee: agent = {} } = {} } = props.conversation;
  return {
    name: agent.name ?? agent.availableName,
    thumbnail: agent.thumbnail,
    status: agent.availabilityStatus,
  };
});
</script>

<template>
  <div class="flex items-end w-full gap-2 pb-1">
    <MessagePreview
      :message="lastNonActivityMessage"
      multi-line
      class="w-full"
      :class="
        unreadCount > 0 ? 'font-medium text-n-slate-12' : 'text-n-slate-11'
      "
    />
    <div class="flex items-center flex-shrink-0 pb-2">
      <Avatar
        v-if="assignee.name"
        :name="assignee.name"
        :src="assignee.thumbnail"
        :size="20"
        :status="assignee.status"
        rounded-full
      />
    </div>
  </div>
</template>
