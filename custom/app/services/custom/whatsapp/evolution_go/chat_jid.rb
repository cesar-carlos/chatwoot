# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::ChatJid
  module_function

  # Protocol ops (react / delete / edit) need the chat addressing WhatsApp
  # actually uses. LID-mode peers must use @lid — a stale @s.whatsapp.net PN
  # can return HTTP 200 from Evolution Go while the reaction never attaches.
  def for_message(message)
    lid_from(message) ||
      jid_from_message_attrs(message) ||
      jid_from_contact(message) ||
      jid_from_contact_inbox(message)
  end

  def lid_from(message)
    candidates = [
      jid_from_message_attrs(message),
      jid_from_contact(message),
      message.conversation&.contact&.identifier
    ]
    candidates.find { |jid| jid.to_s.end_with?('@lid') }
  end

  def jid_from_message_attrs(message)
    attrs = message.content_attributes || {}
    attrs['evolution_go_remote_jid'].presence || attrs[:evolution_go_remote_jid].presence
  end

  def jid_from_contact(message)
    contact = message.conversation&.contact
    contact_attrs = (contact&.additional_attributes || {}).with_indifferent_access
    contact_attrs[Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY].presence
  end

  def jid_from_contact_inbox(message)
    contact_jid = message.conversation&.contact_inbox&.source_id.to_s
    return contact_jid if contact_jid.include?('@')

    phone = contact_jid.gsub(/\D/, '')
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end
end
