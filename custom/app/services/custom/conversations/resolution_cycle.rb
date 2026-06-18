module Custom::Conversations::ResolutionCycle
  module_function

  def start_time(conversation)
    return conversation.created_at unless conversation.inbox.lock_to_single_conversation?

    last_opened_event = conversation.reporting_events.where(
      name: 'conversation_opened'
    ).order(event_end_time: :desc).first

    last_opened_event&.event_end_time || conversation.created_at
  end
end
