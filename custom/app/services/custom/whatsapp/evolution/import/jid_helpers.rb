# frozen_string_literal: true

module Custom::Whatsapp::Evolution::Import::JidHelpers
  private

  def skip_remote_jid?(remote_jid)
    return true if remote_jid.blank?
    return true if remote_jid == 'status@broadcast' && runtime.config['ignore_status_broadcast'] != false
    return true if remote_jid.end_with?('@g.us') && runtime.config['groups_ignore'] != false

    Array(runtime.config['ignore_jids']).any? { |pattern| remote_jid.include?(pattern.to_s) }
  end

  def phone_from_jid(jid)
    phone = jid.to_s.split('@').first.presence
    return if phone.blank?
    return unless phone.match?(/\A\d+\z/)

    normalize_phone(phone)
  end

  def phone_from_message_key(key)
    phone_from_jid(key['remoteJidAlt'].presence || key['remoteJid'])
  end

  def normalize_phone(phone)
    normalized = phone.to_s.gsub(/\D/, '')
    return normalized unless merge_brazil_contacts? && normalized.start_with?('55')

    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(normalized)
  end

  def normalize_source_id(phone)
    normalize_phone(phone)
  end

  def merge_brazil_contacts?
    ActiveModel::Type::Boolean.new.cast(runtime.config['merge_brazil_contacts'])
  end
end
