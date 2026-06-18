class Account::ConversationsResolutionSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.with_auto_resolve.find_each(batch_size: 100) do |account|
      # FORK: skip legacy auto-resolve when workflow rules migration completed
      next if account.workflow_rules_migrated?

      Conversations::ResolutionJob.perform_later(account: account)
    end
  end
end
Account::ConversationsResolutionSchedulerJob.prepend_mod_with('Account::ConversationsResolutionSchedulerJob')
