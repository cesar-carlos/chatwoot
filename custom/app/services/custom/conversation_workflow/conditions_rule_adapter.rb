class Custom::ConversationWorkflow::ConditionsRuleAdapter
  attr_reader :id, :conditions

  def initialize(rule)
    @id = rule.id
    @conditions = rule.conditions
  end

  def authorization_error!
    # Workflow rules do not disable on condition validation failure.
  end
end
