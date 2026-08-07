# frozen_string_literal: true

module Custom::Voice::InboundCallBuilder
  # FORK: inbound voice creates a contact-initiated episode for automation filters
  def resolve_conversation!(contact, contact_inbox)
    Current.conversation_opened_by = Custom::Conversations::OpenedByStamper::CONTACT
    Conversations::Resolver.new(
      inbox: inbox,
      contact_inbox: contact_inbox,
      conversation_params: {
        account_id: account.id,
        inbox_id: inbox.id,
        contact_id: contact.id,
        contact_inbox_id: contact_inbox.id,
        status: :open,
        additional_attributes: {
          Custom::Conversations::OpenedByStamper::ATTRIBUTE_KEY => Custom::Conversations::OpenedByStamper::CONTACT
        }
      }
    ).perform
  ensure
    Current.conversation_opened_by = nil
  end
end

Voice::InboundCallBuilder.prepend_mod_with('Voice::InboundCallBuilder')
