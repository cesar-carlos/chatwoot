class Conversations::Resolver
  # FORK: centralized resolver to keep per-inbox conversation selection consistent
  pattr_initialize [:inbox!, :contact_inbox!, :conversation_params!]

  def perform
    # FORK: serialize lookup/create per contact_inbox to avoid duplicate conversations under concurrent webhooks
    contact_inbox.with_lock do
      find_conversation || ::Conversation.create!(conversation_params)
    end
  end

  private

  def find_conversation
    return contact_inbox.conversations.last if inbox.lock_to_single_conversation?

    contact_inbox.conversations.where.not(status: :resolved).last
  end
end
