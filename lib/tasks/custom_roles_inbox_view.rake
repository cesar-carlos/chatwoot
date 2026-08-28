# FORK: custom role inbox view permission — compatible grant for existing roles
namespace :custom_roles do
  desc 'Grant inbox_view_manage to custom roles that already have conversation permissions'
  task grant_inbox_view_permission: :environment do
    updated = Custom::CustomRoles::GrantInboxViewPermissionService.new.perform
    puts "Granted inbox_view_manage to #{updated} custom role(s)"
  end

  desc 'Report custom roles with overlapping conversation-scope permissions (optional ACCOUNT_ID=)'
  task audit_scope_overlap: :environment do
    results = Custom::CustomRoles::AuditScopeOverlapService.new(account_id: ENV.fetch('ACCOUNT_ID', nil)).perform
    if results.empty?
      puts 'No custom roles with overlapping conversation-scope permissions'
      next
    end

    results.each do |result|
      role = result.role
      puts "account=#{role.account_id} id=#{role.id} name=#{role.name.inspect} " \
           "overlapping=#{result.overlapping.join(',')} effective=#{result.effective}" \
           "#{result.participating ? ' participating=true' : ''}"
    end
    puts "Found #{results.size} overlapping custom role(s)"
  end

  desc 'Set Time Financeiro conversation scope to conversation_team_unassigned_manage (ACCOUNT_ID= CONFIRM=1)'
  task normalize_time_financeiro: :environment do
    account_id = ENV.fetch('ACCOUNT_ID')
    abort 'Refusing to run without CONFIRM=1' unless ENV['CONFIRM'] == '1'

    role = Custom::CustomRoles::NormalizeTimeFinanceiroService.new(account_id: account_id).perform
    puts "Updated #{role.name.inspect} (id=#{role.id}) permissions=#{role.permissions.join(',')}"
  end
end
