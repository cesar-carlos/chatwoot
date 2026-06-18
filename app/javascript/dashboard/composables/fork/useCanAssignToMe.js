// FORK: assignme - permission check aligned with conversation list role filter
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getUserPermissions,
  getUserRole,
} from 'dashboard/helper/permissionsHelper';
import { applyRoleFilter } from 'dashboard/store/modules/conversations/helpers';

export function useCanAssignToMe() {
  const currentUser = useMapGetter('getCurrentUser');
  const currentAccountId = useMapGetter('getCurrentAccountId');
  const userTeams = useMapGetter('teams/getMyTeams');
  const inboxes = useMapGetter('inboxes/getInboxes');

  const role = computed(() =>
    getUserRole(currentUser.value, currentAccountId.value)
  );
  const permissions = computed(() =>
    getUserPermissions(currentUser.value, currentAccountId.value)
  );
  const currentUserId = computed(() => currentUser.value?.id);
  const userInboxIds = computed(() =>
    (inboxes.value || []).map(inbox => inbox.id)
  );

  function canAssignConversationToMe(conversation) {
    const assigneeId = conversation?.meta?.assignee?.id;
    const isUnassigned =
      assigneeId === null ||
      assigneeId === undefined ||
      assigneeId === '' ||
      assigneeId === 0;

    if (!isUnassigned) return false;

    return applyRoleFilter(
      conversation,
      role.value,
      permissions.value,
      currentUserId.value,
      userTeams.value || [],
      userInboxIds.value
    );
  }

  return {
    canAssignConversationToMe,
  };
}
