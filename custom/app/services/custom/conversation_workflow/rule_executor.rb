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

  private

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

    execute_pipeline(conversation)
    create_activity_message(conversation)
    Custom::ConversationWorkflow::AutomationEventDispatcher.new(rule: @rule, conversation: conversation).perform
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- one guard per trigger type
  def conversation_eligible?(conversation)
    return false unless Custom::ConversationWorkflow::ScopeMatcher.new(rule: @rule, conversation: conversation).matches?
    return false if @rule.conversation_inactivity? && conversation.last_activity_at.blank?
    return false if @rule.first_response_overdue? && conversation.first_reply_created_at.present?
    return false if @rule.unassigned_too_long? && conversation.assignee_id.present?
    return false if @rule.pending_stale? && !conversation.pending?
    return false if @rule.customer_no_reply? && !customer_waiting_on_agent_reply?(conversation)
    return false unless Custom::ConversationWorkflow::ThresholdMatcher.new(rule: @rule, conversation: conversation).matched?

    true
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
    dedup = Custom::ConversationWorkflow::ReferenceTimestamp.new(rule: @rule, conversation: conversation).dedup_attributes
    return dedup[:waiting_since_epoch] if attribute == :waiting_since
    return dedup[:last_activity_epoch] if attribute == :last_activity_at

    nil
  end

  def customer_waiting_on_agent_reply?(conversation)
    last_message = conversation.messages.where(message_type: %i[incoming outgoing]).order(created_at: :desc).first
    last_message&.outgoing?
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
