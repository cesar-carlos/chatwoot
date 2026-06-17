// FORK: extracted for merge-safe fork integration
import { computed, unref } from 'vue';
import { useUnreadCount } from './useUnreadCount';

export const useConversationCardFork = ({
  chat,
  chatMetadata,
  canAssignToMe,
  currentUser,
  isAssignPending,
  emit,
}) => {
  const { unreadCount, hasUnread } = useUnreadCount(chat);

  const assignee = computed(() => unref(chatMetadata).assignee || {});

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
    const hasPermission = unref(canAssignToMe);
    const userExists = !!unref(currentUser)?.id;
    const notAssigned = !isAssigned.value;

    return notAssigned && userExists && hasPermission;
  });

  const currentUserAgentInfo = computed(() => ({
    id: unref(currentUser).id,
    name: unref(currentUser).name,
    email: unref(currentUser).email,
    avatar_url: unref(currentUser).avatar_url,
  }));

  const showAssigneeInMeta = showAssignee =>
    showAssignee && assignee.value?.name;

  const messagePreviewPaddingClass = computed(() =>
    showAssignmentButton.value ? 'ltr:pr-24 rtl:pl-24' : ''
  );

  const contentSectionClass =
    'px-0 py-3 border-b group-hover:border-transparent flex-1 border-n-slate-3 min-w-0';

  const fastAssign = e => {
    e.stopPropagation();
    if (unref(isAssignPending)) return;

    emit('assignAgent', currentUserAgentInfo.value, [unref(chat).id]);
  };

  return {
    assignee,
    unreadCount,
    hasUnread,
    showAssignmentButton,
    showAssigneeInMeta,
    messagePreviewPaddingClass,
    contentSectionClass,
    fastAssign,
  };
};
