# frozen_string_literal: true

module Custom::Conversations::MessageWindowService
  private

  def messaging_window
    channel = @conversation.inbox.channel
    return nil if channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'

    super
  end
end

Conversations::MessageWindowService.prepend_mod_with('Conversations::MessageWindowService')
