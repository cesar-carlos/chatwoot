# frozen_string_literal: true

class Wavoip::StaleInProgressCallJob < ApplicationJob
  queue_as :default

  DEFAULT_TIMEOUT_SECONDS = 7200

  def perform(call_id)
    call = Call.find_by(id: call_id)
    return if call.blank?

    transitioned = call.with_lock { transition_to_completed!(call) }
    return unless transitioned

    finalize!(call)
  end

  private

  def transition_to_completed!(call)
    return false unless call.in_progress?

    duration = call.started_at ? (Time.current - call.started_at).to_i : call.duration_seconds
    call.update!(
      status: 'completed',
      duration_seconds: duration,
      end_reason: 'auto_timeout',
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
