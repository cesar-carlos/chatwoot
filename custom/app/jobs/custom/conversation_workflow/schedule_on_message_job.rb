class Custom::ConversationWorkflow::ScheduleOnMessageJob < ApplicationJob
  queue_as :low

  def perform(rule_id:, conversation_id: nil)
    rule = ConversationWorkflowRule.find_by(id: rule_id)
    return if rule.blank? || !rule.active?

    if conversation_id.present?
      conversation = Conversation.find_by(id: conversation_id)
      return if conversation.blank?
      return if rule.agent_no_reply? && conversation.waiting_since.blank?

      Custom::ConversationWorkflow::RuleExecutor.new(account: conversation.account, rule: rule)
                                                .perform_for_conversation(conversation)
      return
    end

    Custom::ConversationWorkflow::RuleExecutor.new(account: rule.account, rule: rule).perform
  end
end
