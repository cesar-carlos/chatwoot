class Custom::ConversationWorkflow::ScopeMatcher
  def initialize(rule:, conversation:)
    @rule = rule
    @conversation = conversation
  end

  def matches?
    return false if @conversation.contact_id.nil?

    if @rule.conversation_inactivity?
      inactivity_matches?
    else
      agent_no_reply_matches?
    end
  end

  private

  def inactivity_matches?
    return false unless @conversation.open?
    return false if @rule.ignore_waiting? && @conversation.waiting_since.present?
    return false if inbox_mismatch?

    true
  end

  def agent_no_reply_matches?
    return false unless @rule.status_names.include?(@conversation.status)
    return false if @conversation.waiting_since.blank?
    return false if @rule.require_no_first_reply? && @conversation.first_reply_created_at.present?
    return false if inbox_mismatch?

    true
  end

  def inbox_mismatch?
    return false if @rule.inbox_ids.blank?

    Array(@rule.inbox_ids).map(&:to_i).exclude?(@conversation.inbox_id)
  end
end
