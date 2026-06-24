class Custom::ConversationWorkflow::ScheduleOnMessageJob < ApplicationJob
  queue_as :low

  def perform(rule_id:, conversation_id: nil, reference_epoch: nil)
    rule = ConversationWorkflowRule.find_by(id: rule_id)
    return if rule.blank? || !rule.active?

    if conversation_id.present?
      perform_for_conversation(rule, conversation_id)
    else
      Custom::ConversationWorkflow::RuleExecutor.new(account: rule.account, rule: rule).perform
    end
  ensure
    clear_schedule_slot!(rule_id, conversation_id, reference_epoch) if conversation_id.present?
  end

  def clear_schedule_slot!(rule_id, conversation_id, reference_epoch)
    prefix = Custom::ConversationWorkflow::ScheduleOnMessageScheduler::REDIS_KEY_PREFIX
    Redis::Alfred.delete("#{prefix}:#{rule_id}:#{conversation_id}:#{reference_epoch}")
  end

  private

  def perform_for_conversation(rule, conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return if conversation_ineligible_for_rule?(rule, conversation)

    Custom::ConversationWorkflow::RuleExecutor.new(account: conversation.account, rule: rule)
                                              .perform_for_conversation(conversation)
  end

  INELIGIBILITY_CHECKS = %i[
    skip_schedulable_waiting?
    skip_first_response_done?
    skip_agent_no_reply?
    skip_unassigned_too_long?
    skip_pending_stale?
    skip_customer_no_reply?
  ].freeze

  def conversation_ineligible_for_rule?(rule, conversation)
    INELIGIBILITY_CHECKS.any? { |check| send(check, rule, conversation) }
  end

  def skip_schedulable_waiting?(rule, conversation)
    ConversationWorkflowRule.schedulable_on_incoming?(rule.trigger_type) && conversation.waiting_since.blank?
  end

  def skip_first_response_done?(rule, conversation)
    rule.first_response_overdue? && conversation.first_reply_created_at.present?
  end

  def skip_agent_no_reply?(rule, conversation)
    rule.agent_no_reply? && conversation.waiting_since.blank?
  end

  def skip_unassigned_too_long?(rule, conversation)
    rule.unassigned_too_long? && conversation.assignee_id.present?
  end

  def skip_pending_stale?(rule, conversation)
    rule.pending_stale? && !conversation.pending?
  end

  def skip_customer_no_reply?(rule, conversation)
    rule.customer_no_reply? && !customer_last_message_outgoing?(conversation)
  end

  def customer_last_message_outgoing?(conversation)
    last_message = conversation.messages.where(message_type: %i[incoming outgoing]).order(created_at: :desc).first
    last_message&.outgoing?
  end
end
