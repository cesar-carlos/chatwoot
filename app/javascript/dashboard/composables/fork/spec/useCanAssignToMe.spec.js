import { useCanAssignToMe } from '../useCanAssignToMe';
import { useMapGetter } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

describe('useCanAssignToMe', () => {
  const unassignedConversation = {
    inbox_id: 10,
    meta: {
      assignee: null,
      team: { id: 7 },
    },
  };

  const assignedConversation = {
    inbox_id: 10,
    meta: {
      assignee: { id: 2 },
    },
  };

  const setup = ({
    user = {
      id: 1,
      accounts: [
        {
          id: 1,
          role: 'agent',
          permissions: [],
        },
      ],
    },
    accountId = 1,
    teams = [{ id: 7 }],
    inboxes = [{ id: 10 }],
  } = {}) => {
    useMapGetter.mockImplementation(getter => {
      const values = {
        getCurrentUser: user,
        getCurrentAccountId: accountId,
        'teams/getMyTeams': teams,
        'inboxes/getInboxes': inboxes,
      };

      return { value: values[getter] };
    });

    return useCanAssignToMe();
  };

  it('allows agents to fast-assign unassigned conversations', () => {
    const { canAssignConversationToMe } = setup();

    expect(canAssignConversationToMe(unassignedConversation)).toBe(true);
    expect(canAssignConversationToMe(assignedConversation)).toBe(false);
  });

  it('allows custom roles with conversation_manage on unassigned conversations', () => {
    const { canAssignConversationToMe } = setup({
      user: {
        id: 1,
        accounts: [
          {
            id: 1,
            custom_role_id: 9,
            permissions: ['conversation_manage'],
          },
        ],
      },
    });

    expect(canAssignConversationToMe(unassignedConversation)).toBe(true);
  });

  it('allows custom roles with conversation_unassigned_manage on unassigned conversations', () => {
    const { canAssignConversationToMe } = setup({
      user: {
        id: 1,
        accounts: [
          {
            id: 1,
            custom_role_id: 9,
            permissions: ['conversation_unassigned_manage'],
          },
        ],
      },
    });

    expect(canAssignConversationToMe(unassignedConversation)).toBe(true);
  });

  it('denies participating_manage on unassigned conversations', () => {
    const { canAssignConversationToMe } = setup({
      user: {
        id: 1,
        accounts: [
          {
            id: 1,
            custom_role_id: 9,
            permissions: ['conversation_participating_manage'],
          },
        ],
      },
    });

    expect(canAssignConversationToMe(unassignedConversation)).toBe(false);
  });

  it('allows team unassigned manage only for conversations in user teams', () => {
    const { canAssignConversationToMe } = setup({
      user: {
        id: 1,
        accounts: [
          {
            id: 1,
            custom_role_id: 9,
            permissions: ['conversation_team_unassigned_manage'],
          },
        ],
      },
      teams: [{ id: 7 }],
    });

    expect(canAssignConversationToMe(unassignedConversation)).toBe(true);
    expect(
      canAssignConversationToMe({
        inbox_id: 10,
        meta: { assignee: null, team: { id: 88 } },
      })
    ).toBe(false);
  });
});
