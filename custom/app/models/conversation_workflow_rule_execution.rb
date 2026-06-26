class ConversationWorkflowRuleExecution < ApplicationRecord
  belongs_to :conversation_workflow_rule
  belongs_to :conversation

  validates :executed_at, presence: true

  def self.record!(rule:, conversation:, waiting_since_epoch: nil, last_activity_epoch: nil)
    create!(
      conversation_workflow_rule: rule,
      conversation: conversation,
      waiting_since_epoch: waiting_since_epoch,
      last_activity_epoch: last_activity_epoch,
      executed_at: Time.current
    )
  end

  def self.release!(rule:, conversation:)
    dedup = Custom::ConversationWorkflow::ReferenceTimestamp.new(rule: rule, conversation: conversation).dedup_attributes
    scope = where(conversation_workflow_rule: rule, conversation: conversation)

    if dedup[:waiting_since_epoch].present?
      scope.where(waiting_since_epoch: dedup[:waiting_since_epoch]).delete_all
    elsif dedup[:last_activity_epoch].present?
      scope.where(last_activity_epoch: dedup[:last_activity_epoch]).delete_all
    else
      scope.delete_all
    end
  end

  def self.clear_unassigned_too_long_for!(conversation:)
    rule_ids = conversation.account.conversation_workflow_rules.unassigned_too_long.select(:id)
    return if rule_ids.blank?

    where(conversation: conversation, conversation_workflow_rule_id: rule_ids).delete_all
  end
end
