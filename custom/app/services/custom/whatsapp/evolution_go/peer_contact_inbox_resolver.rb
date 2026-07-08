# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::PeerContactInboxResolver
  REMOTE_JID_KEY = Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY

  pattr_initialize [:channel!, :key!]

  def find_or_create!
    key_data = key.with_indifferent_access
    peer_jids_for_lookup(key_data).each do |remote_jid|
      existing = find_existing_contact_inbox(remote_jid)
      return existing if existing.present?
    end

    create_contact_inbox!(key_data)
  end

  private

  def inbox
    channel.inbox
  end

  def account
    channel.account
  end

  def config
    channel.provider_config || {}
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(config)
  end

  def peer_jids_for_lookup(key_data)
    [
      key_data[:remoteJid],
      key_data[:remoteJidAlt],
      jid_resolver.resolve_message_jid(key_data)
    ].map(&:to_s).grep(/@/).uniq
  end

  def find_existing_contact_inbox(remote_jid)
    by_remote_jid = inbox.contact_inboxes.joins(:contact)
                         .where('contacts.additional_attributes @> ?', { REMOTE_JID_KEY => remote_jid }.to_json)
                         .first
    return by_remote_jid if by_remote_jid.present?

    if remote_jid.end_with?('@lid')
      by_identifier = inbox.contact_inboxes.joins(:contact)
                           .where(contacts: { identifier: remote_jid })
                           .first
      return by_identifier if by_identifier.present?
    end

    find_existing_contact_inbox_by_phone(remote_jid)
  end

  def find_existing_contact_inbox_by_phone(remote_jid)
    phone = jid_resolver.phone_from_jid(remote_jid)
    return if phone.blank?

    normalized_phone = jid_resolver.normalize_phone(phone)
    source_ids = [normalized_phone, phone].uniq
    by_source = inbox.contact_inboxes.where(source_id: source_ids).first
    return by_source if by_source.present?

    phone_numbers = source_ids.map { |value| "+#{value}" }
    contact = account.contacts
                     .joins(:contact_inboxes)
                     .where(contact_inboxes: { inbox_id: inbox.id })
                     .find_by(phone_number: phone_numbers)
    contact&.contact_inboxes&.find_by(inbox_id: inbox.id)
  end

  def create_contact_inbox!(key_data)
    remote_jid = jid_resolver.resolve_message_jid(key_data)
    phone = jid_resolver.phone_from_message_key(key_data)

    if remote_jid.end_with?('@lid') && phone.blank?
      return create_lid_contact_inbox!(remote_jid)
    end

    return if phone.blank?

    source_id = jid_resolver.normalize_phone(phone)
    contact = account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    apply_remote_jid!(contact, remote_jid.presence || key_data[:remoteJid].to_s)
    contact.name = contact.name.presence || contact.phone_number
    contact.save!

    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: source_id).perform
  end

  def create_lid_contact_inbox!(remote_jid)
    contact = account.contacts.find_or_initialize_by(identifier: remote_jid)
    apply_remote_jid!(contact, remote_jid)
    contact.name = contact.name.presence || remote_jid.split('@').first
    contact.save!

    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: remote_jid).perform
  end

  def apply_remote_jid!(contact, remote_jid)
    return if remote_jid.blank?

    additional = contact.additional_attributes.stringify_keys
    additional[REMOTE_JID_KEY] = remote_jid
    contact.additional_attributes = additional
    contact.identifier = remote_jid if remote_jid.end_with?('@lid')
  end
end
