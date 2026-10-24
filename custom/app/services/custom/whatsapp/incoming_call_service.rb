# frozen_string_literal: true

module Custom::Whatsapp::IncomingCallService
  def reject_disabled_inbound(payload)
    Rails.logger.info "[WHATSAPP CALL] Inbound calls disabled for inbox #{inbox.id}; rejecting call #{payload[:id]}"
    inbox.channel.provider_service.reject_call(payload[:id])
  end

  # FORK: outbound_connected goes to the initiating agent, not the whole account
  def outbound_connected_streams(call)
    token = call.accepted_by_agent&.pubsub_token
    token ? [token] : account_streams
  end
end
