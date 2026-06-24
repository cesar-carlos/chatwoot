# frozen_string_literal: true

class Wavoip::EscalateRingJob < ApplicationJob
  queue_as :default

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return unless call&.ringing? && call.incoming?

    Wavoip::Calls::Broadcaster.new(inbox: call.inbox).broadcast_escalated_ring(call)
  end
end
