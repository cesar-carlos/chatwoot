# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::ChatJid
  module_function

  # Protocol ops (react / delete / edit) and outbound send need the chat
  # addressing WhatsApp actually uses. LID-mode peers must use @lid — a stale
  # @s.whatsapp.net PN (e.g. BR WITH-9 source_id) can fail delivery or silently
  # drop reactions.
  #
  # Group chats: prefer @g.us before any @lid so a polluted contact.identifier
  # cannot rewrite the group conversation to a member LID.
  def for_message(message)
    group_jid_from_message(message) ||
      lid_from(message) ||
      jid_from_message_attrs(message) ||
      jid_from_latest_incoming(message) ||
      jid_from_contact(message) ||
      jid_from_contact_inbox(message)
  end

  def for_conversation(conversation)
    return if conversation.blank?

    group_jid_from_conversation(conversation) ||
      lid_from_conversation(conversation) ||
      jid_from_latest_incoming_conversation(conversation) ||
      jid_from_contact_record(conversation.contact) ||
      jid_from_contact_inbox_record(conversation.contact_inbox)
  end

  def group_jid_from_message(message)
    candidates = [
      message.conversation&.contact_inbox&.source_id,
      message.conversation&.contact&.identifier,
      jid_from_message_attrs(message),
      jid_from_contact(message),
      jid_from_latest_incoming(message)
    ]
    candidates.find { |jid| group_jid?(jid) }
  end

  def group_jid_from_conversation(conversation)
    candidates = [
      conversation.contact_inbox&.source_id,
      conversation.contact&.identifier,
      jid_from_contact_record(conversation.contact),
      jid_from_latest_incoming_conversation(conversation)
    ]
    candidates.find { |jid| group_jid?(jid) }
  end

  def group_jid?(jid)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(jid.to_s)
  end

  def lid_from(message)
    candidates = [
      jid_from_message_attrs(message),
      jid_from_latest_incoming(message),
      jid_from_contact(message),
      message.conversation&.contact&.identifier
    ]
    candidates.find { |jid| jid.to_s.end_with?('@lid') }
  end

  def lid_from_conversation(conversation)
    candidates = [
      jid_from_latest_incoming_conversation(conversation),
      jid_from_contact_record(conversation.contact),
      conversation.contact&.identifier
    ]
    candidates.find { |jid| jid.to_s.end_with?('@lid') }
  end

  def jid_from_message_attrs(message)
    return if message.blank?

    attrs = message.content_attributes || {}
    attrs['evolution_go_remote_jid'].presence || attrs[:evolution_go_remote_jid].presence
  end

  # Fresh outgoing rows (welcome bot) have no evolution_go_remote_jid — reuse the
  # last inbound peer JID so send prefers WITHOUT-9 PN / @lid over source_id.
  def jid_from_latest_incoming(message)
    jid_from_latest_incoming_conversation(message&.conversation)
  end

  def jid_from_latest_incoming_conversation(conversation)
    return if conversation.blank?

    latest = conversation.messages.incoming.order(created_at: :desc).limit(1).first
    jid_from_message_attrs(latest)
  end

  def jid_from_contact(message)
    jid_from_contact_record(message.conversation&.contact)
  end

  def jid_from_contact_record(contact)
    return if contact.blank?

    contact_attrs = (contact.additional_attributes || {}).with_indifferent_access
    contact_attrs[Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY].presence
  end

  def jid_from_contact_inbox(message)
    jid_from_contact_inbox_record(message.conversation&.contact_inbox)
  end

  def jid_from_contact_inbox_record(contact_inbox)
    contact_jid = contact_inbox&.source_id.to_s
    return contact_jid if contact_jid.include?('@')

    phone = contact_jid.gsub(/\D/, '')
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end
end
