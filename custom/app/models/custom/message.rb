module Custom::Message
  extend ActiveSupport::Concern

  prepended do
    after_create_commit :schedule_workflow_rules_on_incoming, if: :incoming?
    after_create_commit :schedule_workflow_rules_on_outgoing, if: :outgoing?
  end

  private

  def schedule_workflow_rules_on_incoming
    schedule_workflow_rules_for(ConversationWorkflowRule.schedulable_on_incoming?)
  end

  def schedule_workflow_rules_on_outgoing
    account = conversation&.account
    return if account.blank?

    account.conversation_workflow_rules.active.customer_no_reply.find_each do |rule|
      next unless account.feature_enabled?('auto_resolve_conversations')
      next if rule.inbox_ids.present? && Array(rule.inbox_ids).exclude?(conversation.inbox_id)

      Custom::ConversationWorkflow::ScheduleOnMessageScheduler.new(
        rule: rule,
        conversation: conversation
      ).perform_for_outgoing_message(self)
    end
  end

  def schedule_workflow_rules_for(trigger_check)
    account = conversation&.account
    return if account.blank?

    account.conversation_workflow_rules.active.find_each do |rule|
      next unless trigger_check.call(rule.trigger_type)
      next unless feature_enabled_for_trigger?(account, rule)
      next if rule.inbox_ids.present? && Array(rule.inbox_ids).exclude?(conversation.inbox_id)
      next if rule.first_response_overdue? && conversation.first_reply_created_at.present?

      Custom::ConversationWorkflow::ScheduleOnMessageScheduler.new(
        rule: rule,
        conversation: conversation
      ).perform
    end
  end

  def feature_enabled_for_trigger?(account, rule)
    flag = Custom::ConversationWorkflow::AccountProcessor::FEATURE_FLAG_BY_TRIGGER[rule.trigger_type]
    flag.blank? || account.feature_enabled?(flag)
  end
end
