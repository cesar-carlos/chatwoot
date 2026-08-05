class Conversations::Resolver
  # FORK: centralized resolver to keep per-inbox conversation selection consistent
  pattr_initialize [:inbox!, :contact_inbox!, { conversation_params: nil }]

  def perform
    # FORK: lazy create params so lookup-only callers avoid eager side effects (e.g. TikTok capabilities API)
    resolve_or_create { conversation_params! }
  end

  def resolve_or_create
    # FORK: single lock for find-or-create; create params evaluated only when needed
    contact_inbox.with_lock do
      find_conversation || ::Conversation.create!(block_given? ? yield : conversation_params!)
    end
  end

  def find
    contact_inbox.with_lock do
      find_conversation
    end
  end

  private

  def conversation_params!
    conversation_params.presence || raise(ArgumentError, 'conversation_params is required to create a conversation')
  end

  def find_conversation
    # FORK: ensure deterministic newest-conversation selection
    return contact_inbox.conversations.order(created_at: :desc).first if inbox.lock_to_single_conversation?

    contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
  end
end

# FORK: Custom::Conversations::Resolver (opened_by stamp, wavoip)
Conversations::Resolver.prepend_mod_with('Conversations::Resolver')
