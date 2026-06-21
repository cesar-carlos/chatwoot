# frozen_string_literal: true

module Custom::Conversations::Resolver
  def find_conversation
    return evolution_find_conversation if evolution_whatsapp_inbox?

    super
  end

  private

  def evolution_whatsapp_inbox?
    inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'
  end

  def evolution_find_conversation
    scope = contact_inbox.conversations.order(created_at: :desc)
    return scope.first if evolution_reopen_conversation?

    scope.where.not(status: :resolved).first
  end

  def evolution_reopen_conversation?
    config = inbox.channel.provider_config || {}
    config.fetch('reopen_conversation', true) != false
  end
end

Conversations::Resolver.prepend_mod_with('Conversations::Resolver')
