module Api::V1::ConversationsHelper
  def current_user_participating?(conversation)
    return false if Current.user.blank?

    if conversation.association(:conversation_participants).loaded?
      conversation.conversation_participants.any? { |participant| participant.user_id == Current.user.id }
    else
      conversation.conversation_participants.exists?(user_id: Current.user.id)
    end
  end
end
