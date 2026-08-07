# frozen_string_literal: true

class Wavoip::Calls::Broadcaster
  def initialize(inbox:)
    @inbox = inbox
  end

  def broadcast_incoming(call)
    return unless call.incoming?
    return if call_already_claimed?(call)

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
    return unless call.incoming?
    return if call_already_claimed?(call)

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
    streams = lifecycle_streams(call)
    return if streams.blank?

    broadcast(call, 'voice_call.outbound_accepted', streams: streams)
  end

  def broadcast_agent_accepted(call, accepted_by_agent_id:)
    agent = User.find_by(id: accepted_by_agent_id)
    streams = lifecycle_streams(call, accepted_by_agent_id: accepted_by_agent_id)
    return if streams.blank?

    broadcast(
      call,
      'voice_call.accepted',
      streams: streams,
      accepted_by_agent_id: accepted_by_agent_id,
      accepted_by_agent_name: agent&.available_name || agent&.name
    )
    Wavoip::Calls::ClearIncomingNotificationsService.new(call: call).perform
  end

  def broadcast_ended(call)
    streams = lifecycle_streams(call)
    return if streams.blank?

    broadcast(
      call,
      'voice_call.ended',
      streams: streams,
      status: call.display_status,
      duration_seconds: call.duration_seconds,
      end_reason: call.end_reason
    )
    Wavoip::Calls::ClearIncomingNotificationsService.new(call: call).perform
  end

  private

  attr_reader :inbox

  def call_already_claimed?(call)
    # Alias kept for readability at broadcast call sites.
    Wavoip::Calls::ClaimGuard.claimed?(call)
  end

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

  # accepted/ended: inbox member base scope (+ accepter). Never fall back to the
  # full account stream — empty recipients mean skip (or accepter-only).
  def lifecycle_streams(call, accepted_by_agent_id: nil)
    tokens = inbox_member_pubsub_tokens.dup
    accepter_id = accepted_by_agent_id.presence || call.accepted_by_agent_id
    if accepter_id.present?
      token = User.find_by(id: accepter_id)&.pubsub_token
      tokens << token if token.present?
    end
    tokens.compact.uniq
  end

  def inbox_member_pubsub_tokens
    user_ids = inbox.member_ids.dup
    channel = inbox.channel
    if channel.is_a?(Channel::Wavoip) && channel.incoming_call_include_administrators?
      user_ids |= channel.account.administrators.ids
    end
    User.where(id: user_ids).pluck(:pubsub_token).compact
  end

  def broadcast(call, event, streams: account_streams, **extra)
    cable_broadcaster.broadcast(call, event, streams: streams, **extra)
  end

  def cable_broadcaster
    @cable_broadcaster ||= Voice::Adapters::ActionCableCallBroadcaster.new(
      account_id: inbox.account_id,
      provider: 'wavoip',
      inbox_id: inbox.id
    )
  end

  def account_streams
    ["account_#{inbox.account_id}"]
  end
end
