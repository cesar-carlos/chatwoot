class ConversationWorkflowRuleSkip < ApplicationRecord
  belongs_to :conversation_workflow_rule

  MAX_PER_RULE = 50

  validates :action_name, :reason, presence: true

  def self.record!(rule:, action_name:, reason:, metadata: {})
    create!(
      conversation_workflow_rule: rule,
      action_name: action_name,
      reason: reason,
      metadata: metadata || {}
    )
    prune!(rule)
  rescue StandardError => e
    Rails.logger.warn(
      '[ConversationWorkflow] failed to record skip ' \
      "(rule_id=#{rule&.id} action=#{action_name}): #{e.class} #{e.message}"
    )
  end

  def self.prune!(rule)
    ids = where(conversation_workflow_rule: rule)
          .order(created_at: :desc)
          .offset(MAX_PER_RULE)
          .pluck(:id)
    where(id: ids).delete_all if ids.any?
  end

  def self.recent_count_by_rule_ids(rule_ids, since: 24.hours.ago)
    where(conversation_workflow_rule_id: rule_ids)
      .where('created_at >= ?', since)
      .group(:conversation_workflow_rule_id)
      .count
  end
end
