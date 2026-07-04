# frozen_string_literal: true

module Custom::MessageTemplates::Template::AutoResolve
  def perform
    return unless Custom::Channels::OutboundText.allowed?(conversation.inbox.channel)

    super
  end
end
