# frozen_string_literal: true

module Custom::Public::Api::V1::Inboxes::ConversationsController
  private

  def create_conversation
    Current.conversation_opened_by = Custom::Conversations::OpenedByStamper::CONTACT
    super
  ensure
    Current.conversation_opened_by = nil
  end
end
