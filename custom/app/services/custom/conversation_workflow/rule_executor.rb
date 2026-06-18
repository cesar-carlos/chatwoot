class Custom::ConversationWorkflow::RuleExecutor
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    base_scope.limit(Limits::BULK_ACTIONS_LIMIT).find_each do |conversation|
      process_conversation(conversation)
    end
  end

  def perform_for_conversation(conversation)
    process_conversation(conversation)
  end

  private

  def base_scope
    if @rule.conversation_inactivity?
      Custom::ConversationWorkflow::Scopes::InactivityScope.new(account: @account, rule: @rule).perform
    else
      Custom::ConversationWorkflow::Scopes::AgentNoReplyScope.new(account: @account, rule: @rule).perform
    end
  end

  def process_conversation(conversation)
    return unless Custom::ConversationWorkflow::ScopeMatcher.new(rule: @rule, conversation: conversation).matches?
    return if @rule.conversation_inactivity? && conversation.last_activity_at.blank?
    return unless Custom::ConversationWorkflow::ThresholdMatcher.new(rule: @rule, conversation: conversation).matched?
    return unless Custom::ConversationWorkflow::ConditionsFilter.new(@rule, conversation).perform
    return unless claim_execution!(conversation)

    execute_pipeline(conversation)
    create_activity_message(conversation)
    Custom::ConversationWorkflow::AutomationEventDispatcher.new(rule: @rule, conversation: conversation).perform
  end

  def execute_pipeline(conversation)
    Current.executed_by = @rule
    if @rule.conversation_inactivity?
      Custom::ConversationWorkflow::TemplateMessageSender.new(conversation: conversation, message: @rule.message).perform if @rule.message.present?
      Custom::ConversationWorkflow::ActionService.new(@rule, @account, conversation).perform if @rule.actions.present?
      resolve_conversation(conversation) if @rule.resolve_on_match?
    elsif @rule.actions.present?
      Custom::ConversationWorkflow::ActionService.new(@rule, @account, conversation).perform
    end
  ensure
    Current.reset
  end

  def resolve_conversation(conversation)
    Custom::Conversations::ResolveService.new(conversation: conversation, skip_required_attributes: true).perform
  end

  def claim_execution!(conversation)
    ConversationWorkflowRuleExecution.record!(
      rule: @rule,
      conversation: conversation,
      waiting_since_epoch: execution_epoch(conversation, :waiting_since),
      last_activity_epoch: execution_epoch(conversation, :last_activity_at)
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def execution_epoch(conversation, attribute)
    if @rule.agent_no_reply?
      attribute == :waiting_since ? conversation.waiting_since&.to_i : nil
    else
      attribute == :last_activity_at ? conversation.last_activity_at&.to_i : nil
    end
  end

  def create_activity_message(conversation)
    content = I18n.t(
      'conversations.activity.workflow_rule.executed',
      rule_name: @rule.name
    )
    params = {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
    ::Conversations::ActivityMessageJob.perform_later(conversation, params)
  end
end
