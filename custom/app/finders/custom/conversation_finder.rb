# frozen_string_literal: true

module Custom::ConversationFinder
  def find_all_conversations
    super
    # Drop rows whose contact was already deleted (no FK; list JSON would 500).
    @conversations = @conversations.joins(:contact)
  end
end
