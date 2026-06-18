class Custom::ConversationWorkflow::SchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.joins(:conversation_workflow_rules)
           .where(conversation_workflow_rules: { active: true })
           .distinct
           .find_each(batch_size: 100) do |account|
      Custom::ConversationWorkflow::AccountProcessor.new(account).perform
    end
  end
end
