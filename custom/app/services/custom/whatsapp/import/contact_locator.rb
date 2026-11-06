# frozen_string_literal: true

# Finds the contact that already represents an address-book phone in this inbox.
# Brazil mobile variants are consulted only when the inbox asked to merge them.
class Custom::Whatsapp::Import::ContactLocator
  pattr_initialize [:account!, :inbox!, { merge_brazil: false }]

  def find(phone)
    digits = phone.to_s.gsub(/\D/, '')
    return if digits.blank?

    candidates = phone_candidates(digits)
    contact_for_source_id(candidates) || contact_for_phone(candidates)
  end

  private

  def phone_candidates(digits)
    return [digits] unless merge_brazil && digits.start_with?('55')

    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.contact_candidates(digits)
  end

  # The inbox link that already has the conversation receives the address book.
  # A second contact that only shares the other phone spelling must not win.
  def contact_for_source_id(candidates)
    matches = inbox.contact_inboxes.where(source_id: candidates).includes(:contact).to_a
    Custom::Whatsapp::ContactInboxPreference.choose(matches)&.contact
  end

  def contact_for_phone(candidates)
    candidates.each do |digits|
      contact = account.contacts.find_by(phone_number: "+#{digits}")
      return contact if contact
    end

    nil
  end
end
