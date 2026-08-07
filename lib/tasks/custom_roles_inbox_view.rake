# FORK: custom role inbox view permission — compatible grant for existing roles
namespace :custom_roles do
  desc 'Grant inbox_view_manage to custom roles that already have conversation permissions'
  task grant_inbox_view_permission: :environment do
    updated = Custom::CustomRoles::GrantInboxViewPermissionService.new.perform
    puts "Granted inbox_view_manage to #{updated} custom role(s)"
  end
end
