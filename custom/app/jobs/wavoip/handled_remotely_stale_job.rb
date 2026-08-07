# frozen_string_literal: true

# HANDLED_REMOTELY was deferred while the dashboard already claimed a still-
# ringing call (awaiting ACTIVE). If neither ACTIVE nor ENDED arrives, close
# the call as handled_remotely so it does not stick in ringing forever.
class Wavoip::HandledRemotelyStaleJob < ApplicationJob
  queue_as :default

  WAIT_SECONDS = 2.minutes.to_i
  LOCK_TTL_BUFFER_SECONDS = 60

  def self.schedule_if_needed(call)
    lock_key = "wavoip:handled_remotely_stale:#{call.id}"
    acquired = Rails.cache.write(
      lock_key,
      true,
      unless_exist: true,
      expires_in: (WAIT_SECONDS + LOCK_TTL_BUFFER_SECONDS).seconds
    )
    return false unless acquired

    set(wait: WAIT_SECONDS.seconds).perform_later(call.id)
    true
  end

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    transitioned = call.with_lock { transition_handled_remotely!(call) }
    return unless transitioned

    Wavoip::Calls::CallFinalizer.finalize_ended!(
      call,
      broadcaster: Wavoip::Calls::Broadcaster.new(inbox: call.inbox)
    )
  end

  private

  def transition_handled_remotely!(call)
    return false unless call.ringing?
    return false unless Wavoip::Calls::ClaimGuard.claimed?(call)

    call.update!(
      status: 'completed',
      end_reason: 'handled_remotely',
      meta: (call.meta || {}).merge(
        'ended_at' => Time.zone.now.to_i,
        'handled_remotely_stale' => true,
        'wavoip_status' => 'HANDLED_REMOTELY'
      )
    )
    true
  end
end
