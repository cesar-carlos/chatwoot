class Custom::CustomRoles::GrantInboxViewPermissionService
  CONVERSATION_PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_team_unassigned_manage
    conversation_participating_manage
  ].freeze

  INBOX_VIEW_PERMISSION = 'inbox_view_manage'.freeze

  def perform
    updated = 0

    CustomRole.find_each do |role|
      next unless needs_grant?(role)

      role.update!(permissions: role.permissions + [INBOX_VIEW_PERMISSION])
      updated += 1
    end

    updated
  end

  private

  def needs_grant?(role)
    permissions = Array(role.permissions)
    return false if permissions.include?(INBOX_VIEW_PERMISSION)

    permissions.intersect?(CONVERSATION_PERMISSIONS)
  end
end
