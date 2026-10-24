# frozen_string_literal: true

# Sets Current.conversation_opened_by for the duration of an inbound create.
# Conversations::Resolver copies it onto additional_attributes; direct
# Conversation.create! paths pick it up in Custom::Conversation.
module Custom::Conversations::IncomingOpenedBy
  def perform
    Custom::Conversations::OpenedByStamper.with_current(opened_by_origin) { super }
  end

  def opened_by_origin
    Custom::Conversations::OpenedByStamper::CONTACT
  end
end
