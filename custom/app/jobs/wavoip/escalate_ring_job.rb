# frozen_string_literal: true

class Wavoip::EscalateRingJob < ApplicationJob
  queue_as :default

  def perform(call_id)
    call = Call.find_by(id: call_id)
    # Still ringing until webhook ACTIVE, but an agent may already have claimed
    # the call via join/PATCH — do not re-notify other agents after accept.
    return unless call&.ringing? && call.incoming?
    return if Wavoip::Calls::ClaimGuard.claimed?(call)

    Wavoip::Calls::Broadcaster.new(inbox: call.inbox).broadcast_escalated_ring(call)
  end
end
