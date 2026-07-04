# frozen_string_literal: true

class Wavoip::Calls::AssignAcceptedAgentService
  def initialize(call:)
    @call = call
  end

  def perform!
    return if call.accepted_by_agent_id.present?

    agent_id = Wavoip::Calls::JoiningAgentCache.read(call.id)
    return if agent_id.blank?

    agent = User.find_by(id: agent_id)
    return if agent.blank?

    call.update!(accepted_by_agent_id: agent.id)
    Wavoip::Calls::JoiningAgentCache.delete(call.id)
    call
  end

  private

  attr_reader :call
end
