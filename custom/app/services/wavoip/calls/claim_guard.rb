# frozen_string_literal: true

# Single source of truth for "an agent already accepted this inbound call".
# Used by Broadcaster, EscalateRingJob, and InboundPushService so ring/push
# stop once `accepted_by_agent_id` is persisted — even while status is still
# `ringing` awaiting webhook ACTIVE.
#
# Intentionally does NOT treat JoiningAgentCache alone as claimed: join can
# succeed and PATCH accept can still fail; blocking escalate/push on cache-only
# would leave other agents ringing with no `voice_call.accepted` dismiss.
# Double-accept races are enforced on join/PATCH via JoiningAgentCache instead.
module Wavoip::Calls::ClaimGuard
  module_function

  def claimed?(call)
    return false if call.blank?

    call.accepted_by_agent_id.present?
  end
end
