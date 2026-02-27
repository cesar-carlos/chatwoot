<script setup>
import { computed, ref, watch } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import UnreadCountBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadCountBadge.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
  enableContextMenu: { type: Boolean, default: false },
  allowedContextMenuOptions: { type: Array, default: () => [] },
  isAssignPending: { type: Boolean, default: false },
  canAssignToMe: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);
const showContextMenu = ref(false);
const contextMenu = ref({
  x: null,
  y: null,
});

const currentChat = useMapGetter('getSelectedChat');
const inboxesList = useMapGetter('inboxes/getInboxes');
const activeInbox = useMapGetter('getSelectedInbox');
const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');

const chatMetadata = computed(() => props.chat.meta || {});

// FORK: guard against null/undefined assignee payloads in conversation meta.
const assignee = computed(() => chatMetadata.value.assignee || {});
// FORK: assignme - Robust check for unassigned state - treat null, undefined, empty object, or missing id as unassigned
const isAssigned = computed(() => {
  if (!assignee.value) return false;
  const assigneeId = assignee.value.id;
  return (
    assigneeId !== null &&
    assigneeId !== undefined &&
    assigneeId !== '' &&
    assigneeId !== 0
  );
});
const showAssignmentButton = computed(() => {
  // FORK: assignme - Show button if conversation is unassigned AND user is logged in AND has permission
  const hasPermission = props.canAssignToMe;
  const userExists = !!currentUser.value?.id;
  const notAssigned = !isAssigned.value;

  return notAssigned && userExists && hasPermission;
});

const currentUserAgentInfo = computed(() => ({
  id: currentUser.value.id,
  name: currentUser.value.name,
  email: currentUser.value.email,
  avatar_url: currentUser.value.avatar_url,
}));

const senderId = computed(() => chatMetadata.value.sender?.id);

const currentContact = computed(() => {
  return senderId.value
    ? store.getters['contacts/getContact'](senderId.value)
    : {};
});

const isActiveChat = computed(() => {
  return currentChat.value.id === props.chat.id;
});

const unreadCount = computed(() => props.chat.unread_count);
// FORK: unread badge over avatar - normalize unread count to keep badge rendering safe.
const unreadCount = computed(() => {
  const parsedUnreadCount = Number(props.chat.unread_count);
  if (Number.isNaN(parsedUnreadCount) || parsedUnreadCount <= 0) {
    return 0;
  }

  return Math.floor(parsedUnreadCount);
});

const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const showMetaSection = computed(() => {
  return (
    props.showInboxName ||
    (props.showAssignee && props.assignee.name) ||
    showInboxName.value ||
    // FORK: avoid runtime TypeError when assignee is absent.
    (props.showAssignee && assignee.value?.name) ||
    props.chat.priority
  );
});

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

const showLabelsSection = computed(() => {
  return props.chat.labels?.length > 0 || hasSlaPolicyId.value;
});

const messagePreviewClass = computed(() => {
  let previewPaddingClass = '';
  if (showAssignmentButton.value) {
    previewPaddingClass = 'ltr:pr-24 rtl:pl-24';
  }

  return [
    hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
    // FORK: assignme - Reserve width so message preview doesn't overlap fast-assign action.
    previewPaddingClass,
  ];
});

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);
const closeContextMenu = () => {
  emit('contextMenuToggle', false);
  showContextMenu.value = false;
  contextMenu.value.x = null;
  contextMenu.value.y = null;
};

const onUpdateConversation = (status, snoozedUntil) => {
  closeContextMenu();
  emit('updateConversationStatus', props.chat.id, status, snoozedUntil);
};

const onAssignAgent = agent => {
  emit('assignAgent', agent, [props.chat.id]);
  closeContextMenu();
};

const onAssignLabel = label => {
  emit('assignLabel', [label.title], [props.chat.id]);
};

const onRemoveLabel = label => {
  emit('removeLabel', [label.title], [props.chat.id]);
};

const onAssignTeam = team => {
  emit('assignTeam', team, props.chat.id);
  closeContextMenu();
};

const markAsUnread = () => {
  emit('markAsUnread', props.chat.id);
  closeContextMenu();
};

const markAsRead = () => {
  emit('markAsRead', props.chat.id);
  closeContextMenu();
};

const assignPriority = priority => {
  emit('assignPriority', priority, props.chat.id);
  closeContextMenu();
};

const deleteConversation = () => {
  emit('deleteConversation', props.chat.id);
  closeContextMenu();
};

const fastAssign = e => {
  // FORK: assignme - Prevent card navigation on button click and guard against concurrent requests.
  e.stopPropagation();
  if (props.isAssignPending) return;

  emit('assignAgent', currentUserAgentInfo.value, [props.chat.id]);
};
</script>

<template>
  <div
    class="relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full py-0 cursor-pointer conversation border-b border-n-slate-3 hover:border-n-surface-1 hover:bg-n-alpha-1 dark:hover:bg-n-alpha-3 group hover:z-[1] before:content-[none] before:absolute before:-top-px before:inset-x-0 before:h-px before:bg-n-surface-1 before:pointer-events-none hover:before:content-['']"
    :class="{
      'active animate-card-select bg-n-background !border-n-surface-1':
        isActiveChat,
      'selected bg-n-slate-2 !border-n-surface-1': selected,
      'px-0': compact,
      'px-3': !compact,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <div
      class="relative"
      :class="!showInboxName ? 'mt-4' : 'mt-8'"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="currentContact.name ?? ''"
        :src="currentContact.thumbnail"
        :size="40"
        :status="currentContact.availability_status"
        hide-offline-status
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
      <!-- FORK: unread badge over avatar -->
      <UnreadCountBadge
        v-if="!hideThumbnail"
        :count="unreadCount"
        class="absolute z-20 -top-1 ltr:-left-1 rtl:-right-1"
      />
    </div>
    <div class="px-0 py-3 flex-1 min-w-0 border-line">
    <!-- FORK: assignme - Keep card height stable across lists after assignment changes. -->
    <div
      class="px-0 py-3 border-b group-hover:border-transparent flex-1 border-n-slate-3 min-w-0"
    >
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1"
        :class="{
          'ltr:ml-2 rtl:mr-2': !compact,
          'mx-2': compact,
        }"
      >
        <InboxName v-if="showInboxName" :inbox="inbox" class="flex-1 min-w-0" />
        <div
          class="flex items-baseline gap-2 flex-shrink-0"
          :class="{
            'flex-1 justify-between': !showInboxName,
          }"
        >
          <span
            v-if="showAssignee && assignee.name"
            class="text-n-slate-11 text-xs font-medium leading-3 py-0.5 px-0 inline-flex items-center truncate"
          >
            <fluent-icon icon="person" size="12" class="text-n-slate-11" />
            {{ assignee.name }}
          </span>
          <CardPriorityIcon
            :priority="chat.priority"
            class="flex-shrink-0 !size-3.5"
          />
        </div>
      </div>
      <h4
        class="conversation--user text-sm my-0 mx-2 capitalize pt-0.5 text-ellipsis overflow-hidden whitespace-nowrap flex-1 min-w-0 ltr:pr-16 rtl:pl-16 text-n-slate-12"
        :class="hasUnread ? 'font-semibold' : 'font-medium'"
      >
        {{ currentContact.name }}
      </h4>
      <VoiceCallStatus
        v-if="voiceCallData.status"
        key="voice-status-row"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-else-if="lastMessageInChat"
        key="message-preview"
        :message="lastMessageInChat"
        class="my-0 mx-2 leading-6 h-6 flex-1 min-w-0 text-sm"
        :class="messagePreviewClass"
      />
      <p
        v-else
        key="no-messages"
        class="text-n-slate-11 text-sm my-0 mx-2 leading-6 h-6 flex-1 min-w-0 overflow-hidden text-ellipsis whitespace-nowrap"
        :class="messagePreviewClass"
      >
        <fluent-icon
          size="16"
          class="-mt-0.5 align-middle inline-block text-n-slate-10"
          icon="info"
        />
        <span class="mx-0.5">
          {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
        </span>
      </p>
      <div
        class="absolute flex flex-col ltr:right-3 rtl:left-3"
        :class="showMetaSection ? 'top-8' : 'top-4'"
      >
        <span class="ml-auto font-normal leading-4 text-xxs">
          <TimeAgo
            :last-activity-timestamp="chat.timestamp"
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="ltr:ml-auto rtl:mr-auto mt-1"
        />
        <button
          v-show="showAssignmentButton"
          :key="`assign-btn-${chat.id}-${assignee?.id || 'unassigned'}`"
          v-tooltip.bottom="$t('CONVERSATION.FAST_ASSIGN')"
          type="button"
          class="mt-1 ltr:ml-auto rtl:mr-auto bg-n-slate-5 dark:bg-n-slate-7 text-n-slate-12 text-xxs px-1.5 py-0.5 rounded font-medium transition-all duration-200 hover:bg-n-slate-6 dark:hover:bg-n-slate-8"
          :class="{ 'opacity-70 pointer-events-none': isAssignPending }"
          :disabled="isAssignPending"
          :aria-label="$t('CONVERSATION.FAST_ASSIGN')"
          @click="fastAssign($event)"
        >
          <template v-if="isAssignPending">
            <Spinner
              :size="10"
              class="text-n-slate-12 ltr:mr-1 rtl:ml-1 inline-block"
            />
          </template>
          {{ $t('CONVERSATION.FAST_ASSIGN') }}
        </button>
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
  </div>
</template>
