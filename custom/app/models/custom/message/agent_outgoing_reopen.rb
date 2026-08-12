# frozen_string_literal: true

# Reopens resolved/snoozed conversations when a human agent sends a public outgoing reply.
# Incoming reopen stays in OpenedByTracking / Message#reopen_conversation.
# Wavoip voice calls keep ConversationReopenService via WavoipConversationCycle.
module Custom::Message::AgentOutgoingReopen
  private

  def reopen_conversation
    reopen_for_agent_outgoing!
    super
  end

  def reopen_for_agent_outgoing!
    return unless should_reopen_for_agent_outgoing?

    Custom::Conversations::OpenedByStamper.stamp!(
      conversation,
      Custom::Conversations::OpenedByStamper::AGENT
    )
    conversation.open!
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- sequential reopen guards
  def should_reopen_for_agent_outgoing?
    return false if conversation.muted?
    return false unless outgoing?
    return false if private?
    return false unless sender.is_a?(User)
    return false if content_attributes['automation_rule_id'].present?
    return false if additional_attributes['campaign_id'].present?
    return false if content_attributes['external_echo'].present?
    return false if voice_call?
    return false if history_import_message?

    conversation.resolved? || conversation.snoozed?
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
