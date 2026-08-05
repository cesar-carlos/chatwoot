class Custom::ConversationWorkflow::RuleExecutor
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    # find_each ignores ORDER BY — load the limited ordered batch explicitly.
    ordered_base_scope.limit(Limits::BULK_ACTIONS_LIMIT).to_a.each do |conversation|
      process_conversation(conversation)
    end
  end

  def matching_scope
    base_scope
  end

  def self.matching_scope(account:, rule:)
    new(account: account, rule: rule).matching_scope
  end

  def perform_for_conversation(conversation)
    process_conversation(conversation)
  end

  def eligible?(conversation)
    conversation_eligible?(conversation)
  end

  def fully_eligible?(conversation)
    conversation_eligible?(conversation) &&
      Custom::ConversationWorkflow::ConditionsFilter.new(@rule, conversation).perform
  end

  private

  def ordered_base_scope
    column = order_column_for_trigger
    return base_scope if column.blank?

    base_scope.order(Arel.sql("#{column} ASC NULLS LAST"))
  end

  def order_column_for_trigger
    case @rule.trigger_type
    when 'conversation_inactivity', 'pending_stale'
      'conversations.last_activity_at'
    when 'agent_no_reply', 'first_response_overdue'
      'conversations.waiting_since'
    when 'unassigned_too_long'
      'conversations.created_at'
    when 'customer_no_reply'
      'conversations.last_activity_at'
    end
  end

  def base_scope
    scope_class = {
      'conversation_inactivity' => Custom::ConversationWorkflow::Scopes::InactivityScope,
      'agent_no_reply' => Custom::ConversationWorkflow::Scopes::AgentNoReplyScope,
      'first_response_overdue' => Custom::ConversationWorkflow::Scopes::FirstResponseOverdueScope,
      'unassigned_too_long' => Custom::ConversationWorkflow::Scopes::UnassignedTooLongScope,
      'pending_stale' => Custom::ConversationWorkflow::Scopes::PendingStaleScope,
      'customer_no_reply' => Custom::ConversationWorkflow::Scopes::CustomerNoReplyScope
    }[@rule.trigger_type]
    raise ArgumentError, "Unknown trigger_type: #{@rule.trigger_type}" if scope_class.blank?

    scope_class.new(account: @account, rule: @rule).perform
  end

  def process_conversation(conversation)
    return unless conversation_eligible?(conversation)
    return unless Custom::ConversationWorkflow::ConditionsFilter.new(@rule, conversation).perform
    return unless claim_execution!(conversation)

    begin
      execute_pipeline(conversation)
    rescue StandardError => e
      ConversationWorkflowRuleExecution.release!(rule: @rule, conversation: conversation)
      ChatwootExceptionTracker.new(e, account: @account).capture_exception
      return
    end

    create_activity_message(conversation)
    Custom::ConversationWorkflow::AutomationEventDispatcher.new(rule: @rule, conversation: conversation).perform
  end

  def conversation_eligible?(conversation)
    return false unless Custom::ConversationWorkflow::ScopeMatcher.new(rule: @rule, conversation: conversation).matches?
    return false if @rule.conversation_inactivity? && conversation.last_activity_at.blank?
    return false unless Custom::ConversationWorkflow::ThresholdMatcher.new(rule: @rule, conversation: conversation).matched?

    true
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
    dedup = Custom::ConversationWorkflow::ReferenceTimestamp.new(rule: @rule, conversation: conversation).dedup_attributes
    ConversationWorkflowRuleExecution.record!(
      rule: @rule,
      conversation: conversation,
      waiting_since_epoch: dedup[:waiting_since_epoch],
      last_activity_epoch: dedup[:last_activity_epoch]
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
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
