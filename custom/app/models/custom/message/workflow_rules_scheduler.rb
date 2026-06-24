# frozen_string_literal: true

# Schedules ConversationWorkflowRules after incoming/outgoing messages are created.
# Runs for all inboxes, not just Evolution — Evolution-specific guard via history_import_message?.
module Custom::Message::WorkflowRulesScheduler
  private

  def schedule_workflow_rules_on_incoming
    return if history_import_message?

    schedule_workflow_rules_for(ConversationWorkflowRule.method(:schedulable_on_incoming?))
  end

  def schedule_workflow_rules_on_outgoing
    return if history_import_message?

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
      next unless workflow_rule_applies?(rule, account, trigger_check)

      Custom::ConversationWorkflow::ScheduleOnMessageScheduler.new(
        rule: rule,
        conversation: conversation
      ).perform
    end
  end

  def workflow_rule_applies?(rule, account, trigger_check)
    trigger_check.call(rule.trigger_type) &&
      feature_enabled_for_trigger?(account, rule) &&
      rule_applies_to_inbox?(rule) &&
      !first_response_already_sent?(rule)
  end

  def rule_applies_to_inbox?(rule)
    rule.inbox_ids.blank? || Array(rule.inbox_ids).include?(conversation.inbox_id)
  end

  def first_response_already_sent?(rule)
    rule.first_response_overdue? && conversation.first_reply_created_at.present?
  end

  def feature_enabled_for_trigger?(account, rule)
    flag = Custom::ConversationWorkflow::AccountProcessor::FEATURE_FLAG_BY_TRIGGER[rule.trigger_type]
    flag.blank? || account.feature_enabled?(flag)
  end
end
