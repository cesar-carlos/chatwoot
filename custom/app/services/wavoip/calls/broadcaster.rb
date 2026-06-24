# frozen_string_literal: true

class Wavoip::Calls::Broadcaster
  def initialize(inbox:)
    @inbox = inbox
  end

  def broadcast_incoming(call)
    contact = call.contact
    streams = agent_streams(call)
    broadcast(
      call,
      'voice_call.incoming',
      streams: streams,
      caller: { name: contact.name, phone: contact.phone_number, avatar: contact.avatar_url }
    )
    Wavoip::InboundCallPushJob.perform_later(call.id)
  end

  def broadcast_escalated_ring(call)
    contact = call.contact
    streams = escalated_streams(call)
    return if streams.blank?

    broadcast(
      call,
      'voice_call.incoming',
      streams: streams,
      caller: { name: contact.name, phone: contact.phone_number, avatar: contact.avatar_url },
      escalated: true
    )
    Wavoip::InboundCallPushJob.perform_later(call.id)
  end

  def broadcast_accepted(call)
    broadcast(call, 'voice_call.outbound_accepted')
  end

  def broadcast_agent_accepted(call, accepted_by_agent_id:)
    broadcast(
      call,
      'voice_call.accepted',
      accepted_by_agent_id: accepted_by_agent_id
    )
  end

  def broadcast_ended(call)
    broadcast(
      call,
      'voice_call.ended',
      status: call.display_status,
      duration_seconds: call.duration_seconds,
      end_reason: call.end_reason
    )
  end

  private

  attr_reader :inbox

  def agent_streams(call)
    Wavoip::Calls::IncomingCallRecipients.new(
      inbox: inbox,
      conversation: call.conversation
    ).pubsub_tokens
  end

  def escalated_streams(call)
    Wavoip::Calls::IncomingCallRecipients.new(
      inbox: inbox,
      conversation: call.conversation
    ).escalated_pubsub_tokens
  end

  def broadcast(call, event, streams: account_streams, **extra)
    payload = { event: event, data: base_payload(call).merge(extra) }
    streams.each { |stream| ActionCable.server.broadcast(stream, payload) }
  end

  def account_streams
    ["account_#{inbox.account_id}"]
  end

  def base_payload(call)
    {
      account_id: inbox.account_id,
      id: call.id,
      call_id: call.provider_call_id,
      provider: 'wavoip',
      conversation_id: call.conversation_id,
      inbox_id: call.inbox_id
    }
  end
end
