# frozen_string_literal: true

module Custom::Conversations::MessageWindowService
  def can_reply?
    return false unless channel_supports_outbound_text?

    super
  end

  def channel_supports_outbound_text?
    channel = @conversation.inbox.channel
    return channel.supports_outbound_text? if channel.respond_to?(:supports_outbound_text?)

    true
  end

  private

  def messaging_window
    channel = @conversation.inbox.channel
    return nil if channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'

    super
  end
end

Conversations::MessageWindowService.prepend_mod_with('Conversations::MessageWindowService')
