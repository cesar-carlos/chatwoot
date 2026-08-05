# frozen_string_literal: true

module Custom::Conversations::Resolver
  def resolve_or_create(&block)
    # FORK: stamp opened_by on create for automation conditions
    contact_inbox.with_lock do
      find_conversation || ::Conversation.create!(
        Custom::Conversations::OpenedByStamper.merge_create_params(
          block ? block.call : conversation_params!
        )
      )
    end
  end

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
