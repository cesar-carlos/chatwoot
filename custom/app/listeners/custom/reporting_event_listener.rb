module Custom::ReportingEventListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    event_end_time = event.timestamp
    cycle_start_time = Custom::Conversations::ResolutionCycle.start_time(conversation)
    time_to_resolve = event_end_time.to_i - cycle_start_time.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_resolved',
      value: time_to_resolve,
      value_in_business_hours: business_hours(conversation.inbox, cycle_start_time, event_end_time),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: cycle_start_time,
      event_end_time: event_end_time
    )

    create_bot_resolved_event(conversation, reporting_event)
    reporting_event.save!
    safe_rollup(reporting_event)
  end

  def conversation_bot_handoff(event)
    conversation = extract_conversation_and_account(event)[0]
    event_end_time = event.timestamp
    cycle_start_time = Custom::Conversations::ResolutionCycle.start_time(conversation)

    return if bot_handoff_already_recorded?(conversation, cycle_start_time)

    time_to_handoff = event_end_time.to_i - cycle_start_time.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_bot_handoff',
      value: time_to_handoff,
      value_in_business_hours: business_hours(conversation.inbox, cycle_start_time, event_end_time),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: cycle_start_time,
      event_end_time: event_end_time
    )
    reporting_event.save!
    safe_rollup(reporting_event)
  end

  private

  def bot_handoff_already_recorded?(conversation, cycle_start_time)
    scope = conversation.reporting_events.where(name: 'conversation_bot_handoff')
    scope = scope.where(event_start_time: cycle_start_time) if conversation.inbox.lock_to_single_conversation?
    scope.exists?
  end
end
