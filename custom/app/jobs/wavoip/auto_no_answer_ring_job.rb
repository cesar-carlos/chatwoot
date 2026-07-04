# frozen_string_literal: true

# Safety net for Wavoip calls that never receive a terminal webhook (dropped
# webhook, or an SDK-only hangup that only updates the agent's browser).
# Force-closes calls still ringing well past the expected window so they stop
# resurfacing as ghost widgets on every conversation hydrate.
class Wavoip::AutoNoAnswerRingJob < ApplicationJob
  queue_as :default

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    transitioned = call.with_lock { transition_to_no_answer!(call) }
    return unless transitioned

    finalize!(call)
  end

  private

  def transition_to_no_answer!(call)
    return false unless call.ringing?

    call.update!(
      status: 'no_answer',
      end_reason: 'no_answer',
      meta: (call.meta || {}).merge('ended_at' => Time.zone.now.to_i, 'auto_timeout' => true)
    )
    true
  end

  def finalize!(call)
    Wavoip::Calls::CallFinalizer.finalize_ended!(
      call,
      broadcaster: Wavoip::Calls::Broadcaster.new(inbox: call.inbox)
    )
  end
end
