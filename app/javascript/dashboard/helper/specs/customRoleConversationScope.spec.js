import { describe, it, expect } from 'vitest';
import {
  conversationScopePermissionsFrom,
  effectiveConversationScopePermission,
  hasOverlappingConversationScope,
  otherCustomRolePermissionsFrom,
} from '../customRoleConversationScope';
import { AVAILABLE_CUSTOM_ROLE_PERMISSIONS } from 'dashboard/constants/permissions';

describe('customRoleConversationScope', () => {
  it('returns overlapping conversation scopes in hierarchy order', () => {
    expect(
      conversationScopePermissionsFrom([
        'conversation_participating_manage',
        'conversation_unassigned_manage',
        'contact_manage',
      ])
    ).toEqual([
      'conversation_unassigned_manage',
      'conversation_participating_manage',
    ]);
  });

  it('returns the broadest permission as the effective scope', () => {
    expect(
      effectiveConversationScopePermission([
        'conversation_team_unassigned_manage',
        'conversation_unassigned_manage',
      ])
    ).toBe('conversation_unassigned_manage');
  });

  it('detects overlapping conversation scopes', () => {
    expect(
      hasOverlappingConversationScope(['conversation_unassigned_manage'])
    ).toBe(false);
    expect(
      hasOverlappingConversationScope([
        'conversation_unassigned_manage',
        'conversation_participating_manage',
      ])
    ).toBe(false);
    expect(
      hasOverlappingConversationScope([
        'conversation_manage',
        'conversation_unassigned_manage',
        'conversation_team_unassigned_manage',
        'conversation_participating_manage',
      ])
    ).toBe(false);
    expect(
      hasOverlappingConversationScope([
        'conversation_unassigned_manage',
        'conversation_team_unassigned_manage',
      ])
    ).toBe(true);
  });

  it('lists non-conversation custom role permissions', () => {
    expect(
      otherCustomRolePermissionsFrom(AVAILABLE_CUSTOM_ROLE_PERMISSIONS)
    ).toEqual([
      'inbox_view_manage',
      'inbox_manage',
      'conversation_reply_assigned_only',
      'contact_manage',
      'report_manage',
      'knowledge_base_manage',
    ]);
  });
});
