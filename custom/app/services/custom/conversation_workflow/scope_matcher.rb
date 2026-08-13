class Custom::ConversationWorkflow::ScopeMatcher
  def initialize(rule:, conversation:)
    @rule = rule
    @conversation = conversation
  end

  def matches?
    return false if @conversation.contact_id.nil?

    case @rule.trigger_type
    when 'conversation_inactivity' then inactivity_matches?
    when 'agent_no_reply', 'first_response_overdue' then waiting_based_matches?
    when 'unassigned_too_long'     then unassigned_matches?
    when 'pending_stale'           then pending_stale_matches?
    when 'customer_no_reply'       then customer_no_reply_matches?
    else false
    end
  end

  private

  def inactivity_matches?
    return false unless @conversation.open?
    return false if @rule.ignore_waiting? && @conversation.waiting_since.present?
    return false if inbox_mismatch?

    true
  end

  # rubocop:disable Metrics/CyclomaticComplexity -- sequential waiting guards
  def waiting_based_matches?
    return false unless @rule.status_names.include?(@conversation.status)
    return false if @conversation.waiting_since.blank?
    return false if @rule.first_response_overdue? && @conversation.first_reply_created_at.present?
    return false if @rule.require_no_first_reply? && @conversation.first_reply_created_at.present?
    return false if inbox_mismatch?

    true
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def unassigned_matches?
    return false unless @conversation.open?
    return false if @conversation.assignee_id.present?
    return false if inbox_mismatch?

    true
  end

  def pending_stale_matches?
    return false unless @conversation.pending?
    return false if inbox_mismatch?

    true
  end

  def customer_no_reply_matches?
    return false unless @conversation.open?
    return false unless last_message_outgoing?
    return false if inbox_mismatch?

    true
  end

  def last_message_outgoing?
    last_msg = @conversation.messages
                            .where(message_type: %i[incoming outgoing])
                            .order(created_at: :desc)
                            .first
    last_msg&.outgoing?
  end

  def inbox_mismatch?
    return false if @rule.inbox_ids.blank?

    Array(@rule.inbox_ids).map(&:to_i).exclude?(@conversation.inbox_id)
  end
end
