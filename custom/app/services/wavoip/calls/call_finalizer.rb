# frozen_string_literal: true

# Single place for the "call status changed" side effects shared by every code
# path that mutates a Call outside the main webhook flow (CallStatusApplier,
# the stale-call safety net, the HANDLED_REMOTELY stub, and the accept
# endpoint): sync the voice_call message bubble and the conversation's cached
# call attributes.
#
# Broadcasting is deliberately NOT bundled into a single "finalize" call for
# every case — different callers emit different events (broadcast_ended,
# broadcast_agent_accepted, ...) depending on what changed on the call.
# `finalize_ended!` covers the common "call just reached a terminal status"
# case where broadcast_ended is always the right event.
class Wavoip::Calls::CallFinalizer
  def self.sync_message_and_conversation!(call, agent: call.accepted_by_agent)
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: agent,
      duration_seconds: call.duration_seconds
    )
    call.sync_conversation_call_attributes!
  end

  def self.finalize_ended!(call, broadcaster:, agent: call.accepted_by_agent)
    sync_message_and_conversation!(call, agent: agent)
    broadcaster.broadcast_ended(call)
  end
end
