# frozen_string_literal: true

# Applies one Evolution address-book row onto a contact without erasing an agent-edited name,
# an existing identifier, or a stored @lid.
class Custom::Whatsapp::Evolution::Import::ContactAttributes
  KEY = Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY

  pattr_initialize [:contact!, :push_name, :remote_jid, :lid]

  def apply!
    contact.name = imported_name
    assign_identifier!
    contact.additional_attributes = remote_jid_attributes
    contact
  end

  private

  def imported_name
    name = push_name.to_s.strip.presence
    return name if name.present? && replaceable_name?
    return contact.name if contact.name.present?

    name || contact.phone_number
  end

  def replaceable_name?
    contact.name.blank? || phone_placeholder_name?
  end

  def phone_placeholder_name?
    phone_number = contact.phone_number.to_s
    return false if phone_number.blank?

    formatted = TelephoneNumber.parse(phone_number).international_number
    contact.name == phone_number || contact.name == formatted
  end

  def assign_identifier!
    return if lid.blank? || contact.identifier.present?
    return if identifier_taken?

    contact.identifier = lid
  end

  def identifier_taken?
    scope = contact.account.contacts.where(identifier: lid)
    scope = scope.where.not(id: contact.id) if contact.persisted?
    scope.exists?
  end

  def remote_jid_attributes
    additional = (contact.additional_attributes || {}).stringify_keys
    additional[KEY] = remote_jid unless additional[KEY].to_s.end_with?('@lid')
    additional
  end
end
