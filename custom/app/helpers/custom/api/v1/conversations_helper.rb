# frozen_string_literal: true

module Custom::Api::V1::ConversationsHelper
  def current_user_participating?(conversation)
    return false if Current.user.blank?

    cached_ids = current_user_participating_conversation_ids if respond_to?(:current_user_participating_conversation_ids)
    return cached_ids.include?(conversation.id) if cached_ids

    if conversation.association(:conversation_participants).loaded?
      conversation.conversation_participants.any? { |participant| participant.user_id == Current.user.id }
    else
      conversation.conversation_participants.exists?(user_id: Current.user.id)
    end
  end
end
