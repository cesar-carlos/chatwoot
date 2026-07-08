# frozen_string_literal: true

# Symmetric to Voice::OutboundCallBuilder (Twilio) but for the WhatsApp Cloud
# Calling API. Key difference: SDP offer comes from the browser before the Call
# record exists, so we accept it as a parameter rather than generating it here.
#
# Usage:
#   call = Voice::OutboundWhatsappCallBuilder.perform!(
#     conversation: conversation,
#     agent:        current_user,
#     sdp_offer:    params[:sdp_offer],
#     provider_service: channel.provider_service
#   )
class Voice::OutboundWhatsappCallBuilder
  def self.perform!(conversation:, agent:, sdp_offer:, provider_service:)
    new(
      conversation: conversation,
      agent: agent,
      sdp_offer: sdp_offer,
      provider_service: provider_service
    ).perform!
  end

  def initialize(conversation:, agent:, sdp_offer:, provider_service:)
    @conversation     = conversation
    @agent            = agent
    @sdp_offer        = sdp_offer
    @provider_service = provider_service
  end

  def perform!
    provider_call_id = nil
    provider_call_id = initiate_provider_call!

    ActiveRecord::Base.transaction do
      call = build_call!(provider_call_id)
      message = Voice::CallMessageBuilder.new(call).perform!
      call.update!(message_id: message.id)
      Whatsapp::Calls::StaleCallTimeoutScheduler.new(call: call).schedule
      call
    end
  rescue StandardError => e
    rollback_provider_call!(provider_call_id) if provider_call_id.present?
    raise e
  end

  private

  attr_reader :conversation, :agent, :sdp_offer, :provider_service

  def contact_phone
    conversation.contact.phone_number&.delete('+')
  end

  def initiate_provider_call!
    result = provider_service.initiate_call(contact_phone, sdp_offer)
    provider_call_id = result.dig('calls', 0, 'id') || result['call_id']
    raise Voice::CallErrors::CallFailed, 'Meta did not return a call ID' if provider_call_id.blank?

    provider_call_id
  end

  def build_call!(provider_call_id)
    conversation.account.calls.create!(
      provider: :whatsapp,
      inbox: conversation.inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider_call_id: provider_call_id,
      direction: :outgoing,
      status: 'ringing',
      accepted_by_agent_id: agent.id,
      meta: { 'sdp_offer' => sdp_offer, 'ice_servers' => Call.default_ice_servers }
    )
  end

  def rollback_provider_call!(provider_call_id)
    provider_service.terminate_call(provider_call_id)
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP CALL] rollback terminate failed for #{provider_call_id}: #{e.class} #{e.message}"
  end
end
