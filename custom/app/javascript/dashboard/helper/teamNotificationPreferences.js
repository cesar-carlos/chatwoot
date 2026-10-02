export const TEAM_ASSIGNMENT_TYPE = 'team_conversation_assignment';

export const withTeamNotificationType = types => {
  const assignmentIndex = types.findIndex(
    type => type.value === 'conversation_assignment'
  );
  const next = [...types];
  next.splice(assignmentIndex + 1, 0, {
    label:
      'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.TEAM_CONVERSATION_ASSIGNMENT',
    value: TEAM_ASSIGNMENT_TYPE,
    description:
      'PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES.TEAM_CONVERSATION_ASSIGNMENT_DESCRIPTION',
  });
  return next;
};

export const TEAM_NOTIFICATION_ICONS = {
  TEAM_CONVERSATION_ASSIGNMENT: ['i-lucide-users', 'text-n-blue-11'],
};
