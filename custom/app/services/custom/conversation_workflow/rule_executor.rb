class Custom::ConversationWorkflow::RuleExecutor
  def initialize(account:, rule:)
    @account = account
    @rule = rule
  end

  def perform
    attempted = 0
    each_candidate_batch do |conversations|
      conversations.each do |conversation|
        next unless process_conversation(conversation)

        attempted += 1
        break if attempted >= Limits::BULK_ACTIONS_LIMIT
      end

      attempted >= Limits::BULK_ACTIONS_LIMIT
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

  def each_candidate_batch
    cursor_time = nil
    cursor_id = nil

    loop do
      conversations = candidate_scope_after(cursor_time, cursor_id).to_a
      break if conversations.empty?

      next_cursor_time = order_value(conversations.last)
      next_cursor_id = conversations.last.id
      break if yield conversations

      cursor_time = next_cursor_time
      cursor_id = next_cursor_id
    end
  end

  def candidate_scope_after(cursor_time, cursor_id)
    scope = ordered_base_scope.limit(Limits::BULK_ACTIONS_LIMIT)
    return scope if cursor_time.nil?

    column = order_column_for_trigger
    scope.where(
      "(#{column} > :cursor_time) OR (#{column} = :cursor_time AND conversations.id > :cursor_id)",
      cursor_time: cursor_time,
      cursor_id: cursor_id
    )
  end

  def ordered_base_scope
    column = order_column_for_trigger
    base_scope.reorder(Arel.sql("#{column} ASC, conversations.id ASC"))
  end

  def order_column_for_trigger
    case @rule.trigger_type
    when 'conversation_inactivity', 'pending_stale', 'customer_no_reply'
      'conversations.last_activity_at'
    when 'agent_no_reply', 'first_response_overdue'
      'conversations.waiting_since'
    when 'unassigned_too_long'
      'conversations.created_at'
    end
  end

  def order_value(conversation)
    attribute = order_column_for_trigger.delete_prefix('conversations.')
    conversation.public_send(attribute)
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
    return false unless conversation_eligible?(conversation)
    return false unless Custom::ConversationWorkflow::ConditionsFilter.new(@rule, conversation).perform
    return false unless claim_execution!(conversation)

    begin
      execute_pipeline(conversation)
    rescue StandardError => e
      ConversationWorkflowRuleExecution.release!(rule: @rule, conversation: conversation)
      ChatwootExceptionTracker.new(e, account: @account).capture_exception
      return true
    end

    create_activity_message(conversation)
    Custom::ConversationWorkflow::AutomationEventDispatcher.new(rule: @rule, conversation: conversation).perform
    true
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
