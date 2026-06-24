module Custom::Conversations::ResolutionCycle
  module_function

  def start_time(conversation)
    return conversation.created_at unless conversation.inbox.lock_to_single_conversation?

    [
      conversation.created_at,
      last_opened_event_time(conversation),
      evolution_pending_cycle_start(conversation)
    ].compact.max
  end

  def last_opened_event_time(conversation)
    conversation.reporting_events.where(
      name: 'conversation_opened'
    ).where.not(event_end_time: nil).order(event_end_time: :desc).pick(:event_end_time)
  end

  def evolution_pending_cycle_start(conversation)
    raw = conversation.additional_attributes&.[]('evolution_pending_since')
    return if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
