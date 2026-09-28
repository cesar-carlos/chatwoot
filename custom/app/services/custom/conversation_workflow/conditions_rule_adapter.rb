class Custom::ConversationWorkflow::ConditionsRuleAdapter
  attr_reader :id, :account, :conditions

  def initialize(rule)
    @id = rule.id
    @account = rule.account
    @conditions = rule.conditions.deep_dup
    # The upstream filter appends query_operator to SQL and requires the final one to be blank.
    # Normalize legacy/API payloads that persisted a trailing AND/OR.
    @conditions.last['query_operator'] = nil if @conditions.present?
  end

  def authorization_error!
    # Workflow rules do not disable on condition validation failure.
  end
end
