# frozen_string_literal: true

class Custom::Whatsapp::Evolution::InboundMessageProcessor
  def self.process(channel, params)
    Whatsapp::IncomingMessageService.new(
      inbox: channel.inbox,
      params: params
    ).perform
  end
end
