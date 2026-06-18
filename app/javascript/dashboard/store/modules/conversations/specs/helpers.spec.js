import { describe, it, expect } from 'vitest';
import { applyRoleFilter, getRoleFilterContext } from '../helpers';

describe('Conversation Helpers', () => {
  describe('#applyRoleFilter', () => {
    const conversationWithAssignee = {
      inbox_id: 10,
      meta: {
        assignee: {
          id: 1,
        },
      },
    };

    const conversationWithDifferentAssignee = {
      inbox_id: 10,
      meta: {
        assignee: {
          id: 2,
        },
      },
    };

    const conversationWithoutAssignee = {
      inbox_id: 10,
      meta: {
        assignee: null,
      },
    };

    const conversationWithoutInboxAccess = {
      inbox_id: 99,
      meta: {
        assignee: null,
      },
    };

    const conversationInUserTeam = {
      inbox_id: 10,
      meta: {
        assignee: null,
        team: {
          id: 7,
        },
      },
    };

    const conversationInOtherTeam = {
      inbox_id: 10,
      meta: {
        assignee: null,
        team: {
          id: 88,
        },
      },
    };

    it('always returns true for administrator role regardless of permissions', () => {
      const role = 'administrator';
      const permissions = [];
      const currentUserId = 1;

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
    });

    it('always returns true for agent role regardless of permissions', () => {
      const role = 'agent';
      const permissions = [];
      const currentUserId = 1;

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId
        )
      ).toBe(true);
    });

    it('returns true for any user with conversation_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_manage'];
      const currentUserId = 1;
      const userInboxIds = [10];

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId,
          [],
          userInboxIds
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId,
          [],
          userInboxIds
        )
      ).toBe(true);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId,
          [],
          userInboxIds
        )
      ).toBe(true);
    });

    describe('with conversation_unassigned_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_unassigned_manage'];
      const currentUserId = 1;
      const userInboxIds = [10];

      it('returns true for conversations assigned to the user', () => {
        expect(
          applyRoleFilter(
            conversationWithAssignee,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(true);
      });

      it('returns true for unassigned conversations', () => {
        expect(
          applyRoleFilter(
            conversationWithoutAssignee,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(true);
      });

      it('returns false for conversations assigned to other users', () => {
        expect(
          applyRoleFilter(
            conversationWithDifferentAssignee,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(false);
      });

      it('returns false for conversations in inboxes without access', () => {
        expect(
          applyRoleFilter(
            conversationWithoutInboxAccess,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(false);
      });
    });

    describe('with conversation_participating_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_participating_manage'];
      const currentUserId = 1;
      const userInboxIds = [10];

      it('returns true for conversations assigned to the user', () => {
        expect(
          applyRoleFilter(
            conversationWithAssignee,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(true);
      });

      it('returns false for unassigned conversations', () => {
        expect(
          applyRoleFilter(
            conversationWithoutAssignee,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(false);
      });

      it('returns false for conversations assigned to other users', () => {
        expect(
          applyRoleFilter(
            conversationWithDifferentAssignee,
            role,
            permissions,
            currentUserId,
            [],
            userInboxIds
          )
        ).toBe(false);
      });
    });

    describe('with conversation_team_unassigned_manage permission', () => {
      const role = 'custom_role';
      const permissions = ['conversation_team_unassigned_manage'];
      const currentUserId = 1;
      const userTeams = [{ id: 7 }];
      const userInboxIds = [10];

      it('returns true for conversations assigned to the user', () => {
        expect(
          applyRoleFilter(
            conversationWithAssignee,
            role,
            permissions,
            currentUserId,
            userTeams,
            userInboxIds
          )
        ).toBe(true);
      });

      it('returns true for unassigned conversations in user team', () => {
        expect(
          applyRoleFilter(
            conversationInUserTeam,
            role,
            permissions,
            currentUserId,
            userTeams,
            userInboxIds
          )
        ).toBe(true);
      });

      it('returns false for unassigned conversations in other team', () => {
        expect(
          applyRoleFilter(
            conversationInOtherTeam,
            role,
            permissions,
            currentUserId,
            userTeams,
            userInboxIds
          )
        ).toBe(false);
      });

      it('returns false when userInboxIds are empty (fail-closed)', () => {
        expect(
          applyRoleFilter(
            conversationInUserTeam,
            role,
            permissions,
            currentUserId,
            userTeams,
            []
          )
        ).toBe(false);
      });

      it('returns false for unassigned conversations without a team', () => {
        expect(
          applyRoleFilter(
            conversationWithoutAssignee,
            role,
            permissions,
            currentUserId,
            userTeams,
            userInboxIds
          )
        ).toBe(false);
      });

      it('returns false when team matches but inbox is not in userInboxIds', () => {
        expect(
          applyRoleFilter(
            conversationInUserTeam,
            role,
            permissions,
            currentUserId,
            userTeams,
            [99]
          )
        ).toBe(false);
      });
    });

    describe('permission precedence', () => {
      const role = 'custom_role';
      const currentUserId = 1;
      const userTeams = [{ id: 7 }];
      const userInboxIds = [10];

      it('conversation_unassigned_manage takes precedence over conversation_team_unassigned_manage', () => {
        const permissions = [
          'conversation_unassigned_manage',
          'conversation_team_unassigned_manage',
        ];

        expect(
          applyRoleFilter(
            conversationInOtherTeam,
            role,
            permissions,
            currentUserId,
            userTeams,
            userInboxIds
          )
        ).toBe(true);
      });
    });

    it('returns false for custom role without any relevant permissions', () => {
      const role = 'custom_role';
      const permissions = ['some_other_permission'];
      const currentUserId = 1;
      const userInboxIds = [10];

      expect(
        applyRoleFilter(
          conversationWithAssignee,
          role,
          permissions,
          currentUserId,
          [],
          userInboxIds
        )
      ).toBe(false);
      expect(
        applyRoleFilter(
          conversationWithDifferentAssignee,
          role,
          permissions,
          currentUserId,
          [],
          userInboxIds
        )
      ).toBe(false);
      expect(
        applyRoleFilter(
          conversationWithoutAssignee,
          role,
          permissions,
          currentUserId,
          [],
          userInboxIds
        )
      ).toBe(false);
    });

    describe('handles edge cases and fail-closed behavior', () => {
      const role = 'custom_role';
      const permissions = ['conversation_unassigned_manage'];
      const currentUserId = 1;

      it('treats undefined assignee as unassigned', () => {
        const conversationWithUndefinedAssignee = {
          inbox_id: 10,
          meta: {
            assignee: undefined,
          },
        };

        expect(
          applyRoleFilter(
            conversationWithUndefinedAssignee,
            role,
            permissions,
            currentUserId,
            [],
            [10]
          )
        ).toBe(true);
      });

      it('handles empty meta object', () => {
        const conversationWithEmptyMeta = {
          inbox_id: 10,
          meta: {},
        };

        expect(
          applyRoleFilter(
            conversationWithEmptyMeta,
            role,
            permissions,
            currentUserId,
            [],
            [10]
          )
        ).toBe(true);
      });

      it('returns false when userInboxIds are not available (fail-closed)', () => {
        expect(
          applyRoleFilter(
            conversationWithoutAssignee,
            role,
            permissions,
            currentUserId,
            []
          )
        ).toBe(false);
      });
    });
  });

  describe('#getRoleFilterContext', () => {
    it('returns role filter context from root getters', () => {
      const rootGetters = {
        getCurrentUser: {
          id: 7,
          accounts: [
            { id: 3, permissions: ['conversation_team_unassigned_manage'] },
          ],
        },
        getCurrentAccountId: 3,
        'teams/getMyTeams': [{ id: 5 }],
        'inboxes/getInboxes': [{ id: 10 }, { id: 11 }],
      };

      expect(getRoleFilterContext(rootGetters)).toEqual({
        currentUser: rootGetters.getCurrentUser,
        currentUserId: 7,
        permissions: ['conversation_team_unassigned_manage'],
        userRole: 'agent',
        userTeams: [{ id: 5 }],
        userInboxIds: [10, 11],
      });
    });
  });
});
