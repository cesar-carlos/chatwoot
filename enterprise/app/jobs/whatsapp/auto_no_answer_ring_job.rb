# frozen_string_literal: true

class Whatsapp::AutoNoAnswerRingJob < ApplicationJob
  queue_as :default

  def perform(call_id)
    call = Call.whatsapp.find_by(id: call_id)
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
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: call.accepted_by_agent,
      duration_seconds: call.duration_seconds
    )
    call.sync_conversation_call_attributes!
    Voice::Adapters::ActionCableCallBroadcaster.new(
      account_id: call.account_id,
      provider: 'whatsapp'
    ).broadcast(
      call,
      'voice_call.ended',
      streams: ["account_#{call.account_id}"],
      status: call.display_status,
      duration_seconds: call.duration_seconds
    )
  end
end
