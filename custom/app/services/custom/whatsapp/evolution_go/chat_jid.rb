# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::ChatJid
  module_function

  def for_message(message)
    attrs = message.content_attributes || {}
    jid = attrs['evolution_go_remote_jid'].presence || attrs[:evolution_go_remote_jid].presence
    return jid if jid.present?

    contact = message.conversation&.contact
    contact_attrs = (contact&.additional_attributes || {}).with_indifferent_access
    jid = contact_attrs[Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY].presence
    return jid if jid.present?

    contact_inbox = message.conversation&.contact_inbox
    contact_jid = contact_inbox&.source_id.to_s
    return contact_jid if contact_jid.include?('@')

    phone = contact_jid.gsub(/\D/, '')
    return if phone.blank?

    "#{phone}@s.whatsapp.net"
  end
end
