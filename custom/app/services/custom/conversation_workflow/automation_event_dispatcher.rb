class Custom::ConversationWorkflow::AutomationEventDispatcher
  EVENT_BY_TRIGGER = {
    'conversation_inactivity' => 'conversation_inactivity_threshold',
    'agent_no_reply' => 'conversation_agent_no_reply'
  }.freeze

  def initialize(rule:, conversation:)
    @rule = rule
    @conversation = conversation
    @account = conversation.account
  end

  def perform
    event_name = EVENT_BY_TRIGGER[@rule.trigger_type]
    return if event_name.blank?

    rules = AutomationRule.where(account_id: @account.id, event_name: event_name, active: true)
    rules.find_each do |automation_rule|
      next unless ::AutomationRules::ConditionsFilterService.new(automation_rule, @conversation).perform

      ::AutomationRules::ActionService.new(automation_rule, @account, @conversation).perform
    end
  end
end
