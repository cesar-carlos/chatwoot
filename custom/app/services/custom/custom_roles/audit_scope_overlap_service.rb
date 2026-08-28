# frozen_string_literal: true

class Custom::CustomRoles::AuditScopeOverlapService
  EXCLUSIVE_PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_team_unassigned_manage
  ].freeze

  UNASSIGNED_PERMISSION = 'conversation_unassigned_manage'
  TEAM_UNASSIGNED_PERMISSION = 'conversation_team_unassigned_manage'
  MANAGE_ALL_PERMISSION = 'conversation_manage'
  PARTICIPATING_PERMISSION = 'conversation_participating_manage'

  Result = Struct.new(:role, :overlapping, :effective, :participating, keyword_init: true)

  def initialize(account_id: nil)
    @account_id = account_id
  end

  def perform
    scope.find_each.filter_map do |role|
      permissions = Array(role.permissions)
      next if permissions.include?(MANAGE_ALL_PERMISSION)
      next unless permissions.include?(UNASSIGNED_PERMISSION) && permissions.include?(TEAM_UNASSIGNED_PERMISSION)

      exclusive = EXCLUSIVE_PERMISSIONS.select { |permission| permissions.include?(permission) }
      Result.new(
        role: role,
        overlapping: exclusive,
        effective: exclusive.first,
        participating: permissions.include?(PARTICIPATING_PERMISSION)
      )
    end
  end

  private

  def scope
    roles = CustomRole.order(:account_id, :id)
    return roles if @account_id.blank?

    roles.where(account_id: @account_id)
  end
end
