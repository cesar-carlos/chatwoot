# frozen_string_literal: true

# Resolves / creates the destination ContactInbox for a history migration peer.
class Custom::Inboxes::HistoryMigration::ContactInboxResolver
  pattr_initialize [:source_inbox!, :target_inbox!]

  def resolve(contact_inbox)
    existing_for_contact = ContactInbox.find_by(
      inbox_id: target_inbox.id,
      contact_id: contact_inbox.contact_id
    )
    return existing_for_contact if existing_for_contact

    source_id = resolved_source_id(contact_inbox)
    return create_api_contact_inbox!(contact_inbox) if source_id.blank? && target_inbox.api?
    return fallback_contact_inbox(contact_inbox) if source_id.blank?

    create_contact_inbox_safely!(contact_inbox.contact, source_id)
  end

  private

  def resolved_source_id(contact_inbox)
    explicit = source_id_for_target(contact_inbox)
    return explicit if explicit.present?

    # API → WA Evolution: contact.identifier may hold the original @g.us JID
    # when the contact came from an Evolution webhook via an API inbox.
    # The UUID stored as contact_inbox.source_id cannot be used in a WA inbox;
    # the identifier is the only recovery path for these group peers.
    identifier_jid = evolution_group_jid_from_identifier(contact_inbox.contact)
    return identifier_jid if identifier_jid.present?

    derived_source_id(contact_inbox.contact)
  end

  def derived_source_id(contact)
    return nil if contact.phone_number.blank?

    if target_inbox.whatsapp?
      contact.phone_number.gsub(/\D/, '')
    elsif target_inbox.twilio_whatsapp?
      "whatsapp:#{contact.phone_number}"
    elsif target_inbox.twilio? || target_inbox.sms?
      contact.phone_number
    elsif target_inbox.email?
      contact.email
    end
  end

  def source_id_for_target(contact_inbox)
    return contact_inbox.source_id if portable_evolution_group?(contact_inbox)
    return contact_inbox.source_id if source_inbox.api? && target_inbox.api?
    return portable_whatsapp_source_id(contact_inbox) if whatsapp_like_pair?

    nil
  end

  def whatsapp_like_pair?
    guard = Custom::Inboxes::HistoryMigration::CompatibilityGuard
    guard.whatsapp_like?(source_inbox) && guard.whatsapp_like?(target_inbox)
  end

  def portable_whatsapp_source_id(contact_inbox)
    sid = contact_inbox.source_id.to_s
    return nil if sid.blank?
    return group_source_id(contact_inbox, sid) if evolution_group_source?(contact_inbox)
    return same_provider_whatsapp_source_id(sid) if same_whatsapp_provider_pair?

    convert_whatsapp_source_id(sid)
  end

  def group_source_id(contact_inbox, sid)
    portable_evolution_group?(contact_inbox) ? sid : nil
  end

  def same_whatsapp_provider_pair?
    (source_inbox.whatsapp? && target_inbox.whatsapp?) ||
      (source_inbox.twilio_whatsapp? && target_inbox.twilio_whatsapp?)
  end

  def same_provider_whatsapp_source_id(sid)
    if source_inbox.whatsapp? && target_inbox.whatsapp?
      return sid if sid.match?(RegexHelper::WHATSAPP_CHANNEL_REGEX)

      return nil
    end

    return sid if sid.match?(RegexHelper::TWILIO_CHANNEL_WHATSAPP_REGEX)

    nil
  end

  def convert_whatsapp_source_id(sid)
    if target_inbox.whatsapp?
      digits = sid.sub(/\Awhatsapp:\+?/, '')
      return digits if digits.match?(RegexHelper::WHATSAPP_CHANNEL_REGEX)

      nil
    elsif target_inbox.twilio_whatsapp?
      return sid if sid.match?(RegexHelper::TWILIO_CHANNEL_WHATSAPP_REGEX)
      return "whatsapp:+#{sid}" if sid.match?(/\A\d{1,15}\z/)
      return "whatsapp:#{sid}" if sid.match?(RegexHelper::WHATSAPP_BSUID_REGEX)

      nil
    end
  end

  def portable_evolution_group?(contact_inbox)
    guard = Custom::Inboxes::HistoryMigration::CompatibilityGuard
    return false unless guard.evolution_family?(source_inbox)
    return false unless guard.evolution_family?(target_inbox)

    evolution_group_source?(contact_inbox)
  end

  def evolution_group_source?(contact_inbox)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(contact_inbox.source_id)
  rescue NameError
    contact_inbox.source_id.to_s.end_with?('@g.us')
  end

  # Recovers the @g.us group JID from contact.identifier when migrating to an
  # Evolution-family inbox. API inboxes store UUID source_ids but preserve the
  # original group JID in contact.identifier (set during webhook processing).
  def evolution_group_jid_from_identifier(contact)
    guard = Custom::Inboxes::HistoryMigration::CompatibilityGuard
    return nil unless guard.evolution_family?(target_inbox)
    return nil unless group_jid_string?(contact.identifier)

    contact.identifier
  end

  def group_jid_string?(identifier)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(identifier)
  rescue NameError
    identifier.to_s.end_with?('@g.us')
  end

  def fallback_contact_inbox(contact_inbox)
    return nil unless portable_evolution_group?(contact_inbox)

    create_contact_inbox_safely!(contact_inbox.contact, contact_inbox.source_id)
  end

  def create_api_contact_inbox!(contact_inbox)
    ContactInbox.create!(
      inbox: target_inbox,
      contact: contact_inbox.contact,
      source_id: SecureRandom.uuid
    )
  rescue ActiveRecord::RecordNotUnique
    ContactInbox.find_by(inbox_id: target_inbox.id, contact_id: contact_inbox.contact_id)
  end

  # Avoid ContactInboxBuilder — its steal path rewrites collisions.
  def create_contact_inbox_safely!(contact, source_id)
    existing = ContactInbox.find_by(inbox_id: target_inbox.id, source_id: source_id)
    if existing
      return existing if existing.contact_id == contact.id

      return nil
    end

    ContactInbox.create!(inbox: target_inbox, contact: contact, source_id: source_id)
  rescue ActiveRecord::RecordNotUnique
    existing = ContactInbox.find_by(inbox_id: target_inbox.id, source_id: source_id)
    return existing if existing&.contact_id == contact.id

    nil
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
