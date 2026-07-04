# frozen_string_literal: true

module Custom::Channels::OutboundText
  def self.allowed?(channel)
    !channel.respond_to?(:supports_outbound_text?) || channel.supports_outbound_text?
  end

  def self.blocks_outgoing_public_message?(channel:, private:, message_type:, content_type:)
    return false if private
    return false unless message_type.to_s == 'outgoing'
    return false if content_type.to_s == 'voice_call'

    !allowed?(channel)
  end
end
