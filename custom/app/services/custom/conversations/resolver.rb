# frozen_string_literal: true

module Custom::Conversations::Resolver
  private

  def find_conversation
    return wavoip_conversation if wavoip_inbox?

    super
  end

  def wavoip_inbox?
    inbox.channel.is_a?(Channel::Wavoip)
  end

  def wavoip_conversation
    contact_inbox.conversations.order(created_at: :desc).first
  end
end

Conversations::Resolver.prepend(Custom::Conversations::Resolver)
