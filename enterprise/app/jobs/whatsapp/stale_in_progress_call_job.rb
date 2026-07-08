# frozen_string_literal: true

class Whatsapp::StaleInProgressCallJob < ApplicationJob
  queue_as :default

  def perform(call_id)
    call = Call.whatsapp.find_by(id: call_id)
    return if call.blank?

    transitioned = call.with_lock { transition_to_completed!(call) }
    return unless transitioned

    finalize!(call)
  end

  private

  def transition_to_completed!(call)
    return false unless call.in_progress?

    duration = call.started_at ? (Time.current - call.started_at).to_i : nil
    call.update!(
      status: 'completed',
      duration_seconds: duration,
      end_reason: 'auto_timeout',
      meta: (call.meta || {}).merge('ended_at' => Time.zone.now.to_i, 'auto_timeout' => true)
    )
    true
  end

  def finalize!(call)
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: call.accepted_by_agent,
      duration_seconds: call.duration_seconds
    )
    call.sync_conversation_call_attributes!
    Voice::Adapters::ActionCableCallBroadcaster.new(
      account_id: call.account_id,
      provider: 'whatsapp'
    ).broadcast(call, 'voice_call.ended', status: call.display_status, duration_seconds: call.duration_seconds)
  end
end
