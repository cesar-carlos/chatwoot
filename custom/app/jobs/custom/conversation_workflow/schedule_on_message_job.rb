class Custom::ConversationWorkflow::ScheduleOnMessageJob < ApplicationJob
  queue_as :low

  def perform(rule_id:, conversation_id: nil)
    rule = ConversationWorkflowRule.find_by(id: rule_id)
    return if rule.blank? || !rule.active?

    if conversation_id.present?
      perform_for_conversation(rule, conversation_id)
    else
      Custom::ConversationWorkflow::RuleExecutor.new(account: rule.account, rule: rule).perform
    end
  ensure
    clear_schedule_slot!(rule_id, conversation_id) if conversation_id.present?
  end

  def clear_schedule_slot!(rule_id, conversation_id)
    Redis::Alfred.delete("#{Custom::ConversationWorkflow::ScheduleOnMessageScheduler::REDIS_KEY_PREFIX}:#{rule_id}:#{conversation_id}")
  end

  private

  def perform_for_conversation(rule, conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return if ConversationWorkflowRule.schedulable_on_incoming?(rule.trigger_type) && conversation.waiting_since.blank?
    return if rule.first_response_overdue? && conversation.first_reply_created_at.present?
    return if rule.agent_no_reply? && conversation.waiting_since.blank?
    return if rule.unassigned_too_long? && conversation.assignee_id.present?
    return if rule.pending_stale? && !conversation.pending?
    return if rule.customer_no_reply? && !customer_last_message_outgoing?(conversation)

    Custom::ConversationWorkflow::RuleExecutor.new(account: conversation.account, rule: rule)
                                              .perform_for_conversation(conversation)
  end

  def customer_last_message_outgoing?(conversation)
    last_message = conversation.messages.where(message_type: %i[incoming outgoing]).order(created_at: :desc).first
    last_message&.outgoing?
  end
end
