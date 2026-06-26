export const WAVOIP_OFFLINE_FALLBACKS = [
  'none',
  'assignee',
  'assignee_or_team_members',
  'assignee_or_inbox_members',
  'assignee_or_inbox_members_and_administrators',
];

export function shouldAgentReceiveWavoipCalls(inbox, { isAdministrator }) {
  if (!inbox) return false;

  const isMember =
    inbox.current_user_inbox_member ?? inbox.currentUserInboxMember;
  if (isMember) return true;
  if (!isAdministrator) return false;

  const includeAdmins =
    inbox.incoming_call_include_administrators ??
    inbox.incomingCallIncludeAdministrators;
  return includeAdmins !== false;
}

export function shouldReceiveWavoipInboundRing({
  inbox,
  isAdministrator,
  availability,
  inboundOnly = true,
}) {
  if (inboundOnly && availability !== 'online') return false;
  if (inbox && !shouldAgentReceiveWavoipCalls(inbox, { isAdministrator })) {
    return false;
  }
  if (inbox?.inbound_calls_enabled === false) return false;

  return true;
}
