import {
  CONVERSATION_PERMISSIONS,
  MANAGE_ALL_CONVERSATION_PERMISSIONS,
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  CONVERSATION_TEAM_UNASSIGNED_PERMISSIONS,
  CONVERSATION_PARTICIPATING_PERMISSIONS,
} from 'dashboard/constants/permissions';

// FORK: custom role team permission normalization — broadest listed first
export const CONVERSATION_SCOPE_HIERARCHY = [
  MANAGE_ALL_CONVERSATION_PERMISSIONS,
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  CONVERSATION_TEAM_UNASSIGNED_PERMISSIONS,
  CONVERSATION_PARTICIPATING_PERMISSIONS,
];

export const conversationScopePermissionsFrom = (permissions = []) =>
  CONVERSATION_SCOPE_HIERARCHY.filter(permission =>
    permissions.includes(permission)
  );

export const effectiveConversationScopePermission = (permissions = []) =>
  CONVERSATION_SCOPE_HIERARCHY.find(permission =>
    permissions.includes(permission)
  ) || null;

export const hasOverlappingConversationScope = (permissions = []) => {
  if (permissions.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS)) return false;

  return (
    permissions.includes(CONVERSATION_UNASSIGNED_PERMISSIONS) &&
    permissions.includes(CONVERSATION_TEAM_UNASSIGNED_PERMISSIONS)
  );
};

export const otherCustomRolePermissionsFrom = (allPermissions = []) =>
  allPermissions.filter(
    permission => !CONVERSATION_PERMISSIONS.includes(permission)
  );
