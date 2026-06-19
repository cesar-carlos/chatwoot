class Custom::ConversationWorkflow::ReferenceTimestamp
  def initialize(rule:, conversation:)
    @rule = rule
    @conversation = conversation
  end

  def value
    case @rule.trigger_type
    when 'conversation_inactivity', 'pending_stale'
      @conversation.last_activity_at
    when 'agent_no_reply', 'first_response_overdue'
      @conversation.waiting_since
    when 'unassigned_too_long'
      @conversation.created_at
    when 'customer_no_reply'
      last_customer_facing_message&.created_at
    end
  end

  def dedup_attributes
    epoch = value&.to_i
    return {} if epoch.blank?

    if @rule.agent_no_reply? || @rule.first_response_overdue?
      { waiting_since_epoch: epoch }
    else
      { last_activity_epoch: epoch }
    end
  end

  private

  def last_customer_facing_message
    @conversation.messages
                 .where(message_type: %i[incoming outgoing])
                 .order(created_at: :desc)
                 .first
  end
end
