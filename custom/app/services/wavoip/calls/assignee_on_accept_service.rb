# frozen_string_literal: true

class Wavoip::Calls::AssigneeOnAcceptService
  def initialize(call:, agent:)
    @call = call
    @agent = agent
  end

  def perform!
    return unless call.incoming?
    return if agent.blank?
    return unless call.inbox.enable_auto_assignment?
    # Preserve an existing assignee; only claim unassigned inbound threads.
    return if call.conversation.assignee_id.present?

    call.conversation.update!(assignee: agent)
  end

  private

  attr_reader :call, :agent
end
