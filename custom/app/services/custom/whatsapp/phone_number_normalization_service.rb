# frozen_string_literal: true

module Custom::Whatsapp::PhoneNumberNormalizationService
  def normalize_and_find_contact_by_provider(raw_number, provider)
    return super unless evolution_inbox_without_brazil_merge?

    clean_number = extract_clean_number(raw_number, provider)
    provider_format = format_for_provider(clean_number, provider)
    existing_contact_inbox = find_existing_contact_inbox(provider_format)

    existing_contact_inbox&.source_id || raw_number
  end

  private

  def evolution_inbox_without_brazil_merge?
    return false unless inbox.channel.is_a?(Channel::Whatsapp) && inbox.channel.provider == 'evolution'

    !ActiveModel::Type::Boolean.new.cast(
      (inbox.channel.provider_config || {})['merge_brazil_contacts']
    )
  end
end

Whatsapp::PhoneNumberNormalizationService.prepend_mod_with('Whatsapp::PhoneNumberNormalizationService')
