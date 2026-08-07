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

    outcome = call.with_lock { transition_or_defer!(call) }
    case outcome
    when :transitioned
      finalize!(call)
    when :deferred_claimed
      schedule_claimed_grace!(call)
    end
  end

  private

  def transition_or_defer!(call)
    return :noop unless call.ringing?

    if Wavoip::Calls::ClaimGuard.claimed?(call) ||
       Wavoip::Calls::JoiningAgentCache.read(call.id).present?
      Rails.logger.info(
        "[WAVOIP] event=claim_skip_auto_no_answer call_id=#{call.id} inbox_id=#{call.inbox_id}"
      )
      return :deferred_claimed
    end

    call.update!(
      status: 'no_answer',
      end_reason: 'no_answer',
      meta: (call.meta || {}).merge('ended_at' => Time.zone.now.to_i, 'auto_timeout' => true)
    )
    :transitioned
  end

  def schedule_claimed_grace!(call)
    Wavoip::ClaimedRingGraceJob.schedule_if_needed(call)
  end

  def finalize!(call)
    Wavoip::Calls::CallFinalizer.finalize_ended!(
      call,
      broadcaster: Wavoip::Calls::Broadcaster.new(inbox: call.inbox)
    )
  end
end
