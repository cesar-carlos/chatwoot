module Custom::Message
  extend ActiveSupport::Concern

  prepended do
    after_create_commit :schedule_workflow_rules_on_incoming, if: :incoming?
  end

  private

  def schedule_workflow_rules_on_incoming
    account = conversation&.account
    return if account.blank?

    account.conversation_workflow_rules.active.find_each do |rule|
      next unless rule.agent_no_reply?
      next unless account.feature_enabled?('conversation_agent_no_reply_rules')
      next if rule.inbox_ids.present? && Array(rule.inbox_ids).exclude?(conversation.inbox_id)

      Custom::ConversationWorkflow::ScheduleOnMessageJob.set(wait: rule.duration_minutes.minutes).perform_later(
        conversation_id: conversation.id,
        rule_id: rule.id
      )
    end
  end
end
