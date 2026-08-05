class ConversationWorkflowRule < ApplicationRecord
  belongs_to :account
  # FK has no ON DELETE CASCADE — must delete executions before the rule.
  has_many :conversation_workflow_rule_executions, dependent: :delete_all

  enum trigger_type: {
    conversation_inactivity: 0,
    agent_no_reply: 1,
    first_response_overdue: 2,
    unassigned_too_long: 3,
    pending_stale: 4,
    customer_no_reply: 5
  }

  SCHEDULABLE_ON_INCOMING = %w[agent_no_reply first_response_overdue].freeze
  # customer_no_reply is scheduled from outgoing messages (see WorkflowRulesScheduler).
  # conversation_inactivity / unassigned_too_long / pending_stale / business-hours rules: cron only.

  def self.schedulable_on_incoming?(trigger_type)
    SCHEDULABLE_ON_INCOMING.include?(trigger_type)
  end

  validates :account_id, :name, :duration_minutes, presence: true
  validates :name, length: { maximum: 255 }
  validates :duration_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 10, less_than_or_equal_to: 1_439_856 }
  validate :json_conditions_format
  validate :json_actions_format
  validate :query_operator_presence
  validate :query_operator_value
  validate :inbox_ids_belong_to_account
  validate :actions_or_outcome_present

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def conditions_attributes
    %w[assignee_id team_id labels priority]
  end

  def actions_attributes
    base = %w[
      add_label remove_label add_private_note send_message assign_agent assign_team
      remove_assigned_agent remove_assigned_team send_webhook_event send_email_to_team
      send_email_transcript change_priority send_message_to_contact
    ]
    base += %w[resolve_conversation] unless conversation_inactivity?
    base.uniq
  end

  def respect_business_hours?
    options.is_a?(Hash) && options['respect_business_hours'] == true
  end

  def require_no_first_reply?
    options.is_a?(Hash) && options['require_no_first_reply'] == true
  end

  def status_names
    statuses = options.is_a?(Hash) ? options['statuses'] : nil
    Array(statuses).presence || ['open']
  end

  private

  def json_conditions_format
    return if conditions.blank?

    attributes = conditions.pluck('attribute_key')
    invalid = attributes - conditions_attributes
    errors.add(:conditions, "Workflow conditions #{invalid.join(',')} not supported.") if invalid.any?
  end

  def json_actions_format
    return if actions.blank?

    attributes = actions.pluck('action_name')
    invalid = attributes - actions_attributes
    errors.add(:actions, "Workflow actions #{invalid.join(',')} not supported.") if invalid.any?
  end

  def query_operator_presence
    return if conditions.blank?

    operators = conditions.select { |obj| obj['query_operator'].nil? }
    errors.add(:conditions, 'Workflow conditions should have query operator.') if operators.length > 1
  end

  def query_operator_value
    conditions.each { |obj| validate_single_condition(obj) }
  end

  def validate_single_condition(condition)
    query_operator = condition['query_operator']
    return if query_operator.blank?

    operator = query_operator.upcase
    errors.add(:conditions, 'Query operator must be either "AND" or "OR"') unless %w[AND OR].include?(operator)
  end

  def inbox_ids_belong_to_account
    return if inbox_ids.blank?

    ids = Array(inbox_ids).map(&:to_i)
    return if account.inboxes.where(id: ids).count == ids.uniq.size

    errors.add(:inbox_ids, 'must belong to the account')
  end

  def actions_or_outcome_present
    if conversation_inactivity?
      return if actions.present? || resolve_on_match? || message.present?

      errors.add(:base, 'Inactivity rules require at least one outcome (actions, resolve_on_match, or message)')
    elsif actions.blank?
      errors.add(:actions, 'must include at least one action')
    end
  end
end
