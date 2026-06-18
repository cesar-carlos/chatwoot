namespace :conversation_workflow do
  desc 'Migrate legacy auto_resolve settings to conversation workflow rules'
  task migrate_legacy: :environment do
    Account.with_auto_resolve.find_each do |account|
      next if account.workflow_rules_migrated?

      Custom::ConversationWorkflow::MigrateLegacyService.new(account).perform
      puts "Migrated account #{account.id}" if account.reload.workflow_rules_migrated?
    end
  end
end
