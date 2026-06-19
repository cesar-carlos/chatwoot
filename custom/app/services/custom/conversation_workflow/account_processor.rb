class Custom::ConversationWorkflow::AccountProcessor
  FEATURE_FLAG_BY_TRIGGER = {
    'conversation_inactivity' => 'auto_resolve_conversations',
    'agent_no_reply' => 'conversation_agent_no_reply_rules',
    'first_response_overdue' => 'conversation_agent_no_reply_rules',
    'unassigned_too_long' => 'conversation_agent_no_reply_rules',
    'pending_stale' => 'conversation_agent_no_reply_rules',
    'customer_no_reply' => 'auto_resolve_conversations'
  }.freeze

  def initialize(account)
    @account = account
  end

  def perform
    @account.conversation_workflow_rules.active.ordered.each do |rule|
      next unless feature_enabled_for?(rule)

      Custom::ConversationWorkflow::RuleExecutor.new(account: @account, rule: rule).perform
    end
  end

  private

  def feature_enabled_for?(rule)
    flag = FEATURE_FLAG_BY_TRIGGER[rule.trigger_type]
    flag.blank? || @account.feature_enabled?(flag)
  end
end
