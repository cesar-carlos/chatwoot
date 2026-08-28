# frozen_string_literal: true

class Custom::CustomRoles::NormalizeTimeFinanceiroService
  SCOPE_PERMISSIONS = Custom::CustomRoles::AuditScopeOverlapService::SCOPE_PERMISSIONS
  TARGET_SCOPE = 'conversation_team_unassigned_manage'
  ROLE_NAME = 'Time Financeiro'

  def initialize(account_id:)
    @account_id = account_id
  end

  def perform
    role = CustomRole.find_by!(account_id: @account_id, name: ROLE_NAME)
    kept = role.permissions - SCOPE_PERMISSIONS
    role.update!(permissions: kept | [TARGET_SCOPE])
    role
  end
end
