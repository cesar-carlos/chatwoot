module Custom::CsatSurveyService
  private

  def csat_already_sent?
    return super unless inbox.lock_to_single_conversation?

    scope = conversation.messages.where(content_type: :input_csat)
    cycle_start_time = csat_cycle_start_time
    return scope.exists? if cycle_start_time.blank?

    scope.exists?(['created_at >= ?', cycle_start_time])
  end

  def csat_cycle_start_time
    last_opened_event = conversation.reporting_events.where(name: 'conversation_opened').order(event_end_time: :desc).first
    last_opened_event&.event_end_time
  end
end
