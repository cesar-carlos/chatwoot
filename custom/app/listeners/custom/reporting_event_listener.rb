module Custom::ReportingEventListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    cycle_start_time = resolution_cycle_start_time(conversation)
    time_to_resolve = conversation.updated_at.to_i - cycle_start_time.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_resolved',
      value: time_to_resolve,
      value_in_business_hours: business_hours(conversation.inbox, cycle_start_time, conversation.updated_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: cycle_start_time,
      event_end_time: conversation.updated_at
    )

    create_bot_resolved_event(conversation, reporting_event)
    reporting_event.save!
  end

  def conversation_bot_handoff(event)
    conversation = extract_conversation_and_account(event)[0]

    bot_handoff_event = ReportingEvent.find_by(conversation_id: conversation.id, name: 'conversation_bot_handoff')
    return if bot_handoff_event.present?

    cycle_start_time = resolution_cycle_start_time(conversation)
    time_to_handoff = conversation.updated_at.to_i - cycle_start_time.to_i

    reporting_event = ReportingEvent.new(
      name: 'conversation_bot_handoff',
      value: time_to_handoff,
      value_in_business_hours: business_hours(conversation.inbox, cycle_start_time, conversation.updated_at),
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      user_id: conversation.assignee_id,
      conversation_id: conversation.id,
      event_start_time: cycle_start_time,
      event_end_time: conversation.updated_at
    )
    reporting_event.save!
  end

  private

  def resolution_cycle_start_time(conversation)
    return conversation.created_at unless conversation.inbox.lock_to_single_conversation?

    last_opened_event = ReportingEvent.where(
      conversation_id: conversation.id,
      name: 'conversation_opened'
    ).order(event_end_time: :desc).first

    last_opened_event&.event_end_time || conversation.created_at
  end
end
