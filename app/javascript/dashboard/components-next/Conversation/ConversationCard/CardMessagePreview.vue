<script setup>
import { computed, toRef } from 'vue';
import { useConversationListPreview } from 'dashboard/composables/useConversationListPreview';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

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

const lastNonActivityMessageContent = useConversationListPreview(
  toRef(props, 'conversation')
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
    <p
      class="w-full mb-0 text-sm leading-7 line-clamp-2"
      :class="
        unreadCount > 0 ? 'font-medium text-n-slate-12' : 'text-n-slate-11'
      "
    >
      {{ lastNonActivityMessageContent }}
    </p>
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
