# frozen_string_literal: true

module Custom::Conversations::MessageWindowService
  def can_reply?
    return false unless Custom::Channels::OutboundText.allowed?(@conversation.inbox.channel)

    super
  end

  private

  def messaging_window
    channel = @conversation.inbox.channel
    return nil if channel.is_a?(Channel::Whatsapp) && MessagingProvider::Capabilities.unlimited_session?(channel.provider)

    super
  end
end

Conversations::MessageWindowService.prepend_mod_with('Conversations::MessageWindowService')
