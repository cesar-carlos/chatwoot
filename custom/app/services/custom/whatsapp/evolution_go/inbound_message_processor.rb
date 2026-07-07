# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::InboundMessageProcessor
  def self.process(channel, params)
    Whatsapp::IncomingMessageService.new(
      inbox: channel.inbox,
      params: params.with_indifferent_access
    ).perform
  end
end
