class Custom::ConversationWorkflow::ConditionsFilter
  def initialize(rule, conversation)
    @rule = rule
    @conversation = conversation
  end

  def perform
    return true if @rule.conditions.blank?

    adapter = Custom::ConversationWorkflow::ConditionsRuleAdapter.new(@rule)
    AutomationRules::ConditionsFilterService.new(adapter, @conversation).perform
  end
end
