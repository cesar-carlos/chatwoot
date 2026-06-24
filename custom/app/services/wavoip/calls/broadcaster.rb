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

  def broadcast_accepted(call)
    broadcast(call, 'voice_call.outbound_accepted', streams: agent_streams(call))
  end

  def broadcast_agent_accepted(call, accepted_by_agent_id:)
    broadcast(
      call,
      'voice_call.accepted',
      streams: agent_streams(call),
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
    online = inbox.available_agents.pluck('users.pubsub_token').compact
    return online if online.present?

    token = call.conversation.assignee&.pubsub_token
    return [token] if token.present?

    user_ids = inbox.member_ids | inbox.account.administrators.ids
    User.where(id: user_ids).pluck(:pubsub_token).compact
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
