module Custom::CsatSurveyService
  private

  def csat_already_sent?
    return super unless inbox.lock_to_single_conversation?

    scope = conversation.messages.where(content_type: :input_csat)
    cycle_start_time = Custom::Conversations::ResolutionCycle.start_time(conversation)

    # FORK: avoid second-precision boundary collisions on cycle reopen
    scope.exists?(['created_at > ?', cycle_start_time])
  end
end
