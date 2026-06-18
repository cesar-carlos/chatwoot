class ConversationWorkflowRuleExecution < ApplicationRecord
  belongs_to :conversation_workflow_rule
  belongs_to :conversation

  validates :executed_at, presence: true

  def self.already_executed?(rule:, conversation:, waiting_since_epoch: nil, last_activity_epoch: nil)
    scope = where(conversation_workflow_rule: rule, conversation: conversation)
    if waiting_since_epoch.present?
      scope.exists?(waiting_since_epoch: waiting_since_epoch)
    elsif last_activity_epoch.present?
      scope.exists?(last_activity_epoch: last_activity_epoch)
    else
      false
    end
  end

  def self.record!(rule:, conversation:, waiting_since_epoch: nil, last_activity_epoch: nil)
    create!(
      conversation_workflow_rule: rule,
      conversation: conversation,
      waiting_since_epoch: waiting_since_epoch,
      last_activity_epoch: last_activity_epoch,
      executed_at: Time.current
    )
  end
end
