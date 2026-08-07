# frozen_string_literal: true

# After AutoNoAnswer skips a claimed/soft-claimed ringing call, schedule a
# longer grace window. If ACTIVE never arrives and the agent never ends the
# SDK session cleanly, force-close so the row does not ring forever.
class Wavoip::ClaimedRingGraceJob < ApplicationJob
  queue_as :default

  GRACE_SECONDS = 45.minutes.to_i
  LOCK_TTL_BUFFER_SECONDS = 60

  def self.schedule_if_needed(call)
    lock_key = "wavoip:claimed_ring_grace:#{call.id}"
    acquired = Rails.cache.write(
      lock_key,
      true,
      unless_exist: true,
      expires_in: (GRACE_SECONDS + LOCK_TTL_BUFFER_SECONDS).seconds
    )
    return false unless acquired

    set(wait: GRACE_SECONDS.seconds).perform_later(call.id)
    true
  end

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    transitioned = call.with_lock { transition_claimed_stale!(call) }
    return unless transitioned

    Wavoip::Calls::CallFinalizer.finalize_ended!(
      call,
      broadcaster: Wavoip::Calls::Broadcaster.new(inbox: call.inbox)
    )
  end

  private

  def transition_claimed_stale!(call)
    return false unless call.ringing?
    return false unless Wavoip::Calls::ClaimGuard.claimed?(call) ||
                        Wavoip::Calls::JoiningAgentCache.read(call.id).present?

    call.update!(
      status: 'no_answer',
      end_reason: 'claimed_stale',
      meta: (call.meta || {}).merge('ended_at' => Time.zone.now.to_i, 'claimed_stale' => true)
    )
    true
  end
end
