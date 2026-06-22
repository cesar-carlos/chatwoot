# frozen_string_literal: true

module Custom::Whatsapp::Evolution::Import::JidHelpers
  private

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(runtime.config)
  end

  def skip_remote_jid?(remote_jid)
    return true if remote_jid.blank?
    return true if remote_jid == 'status@broadcast' && runtime.config['ignore_status_broadcast'] != false
    return true if remote_jid.end_with?('@g.us') && runtime.config['groups_ignore'] != false

    Array(runtime.config['ignore_jids']).any? { |pattern| remote_jid.include?(pattern.to_s) }
  end

  def phone_from_jid(jid)
    jid_resolver.phone_from_jid(jid)
  end

  def phone_from_message_key(key)
    jid_resolver.phone_from_message_key(key)
  end

  def phone_from_contact_record(record)
    jid_resolver.phone_from_record(record)
  end

  def normalize_phone(phone)
    jid_resolver.normalize_phone(phone)
  end

  def normalize_source_id(phone)
    normalize_phone(phone)
  end

  def merge_brazil_contacts?
    ActiveModel::Type::Boolean.new.cast(runtime.config['merge_brazil_contacts'])
  end
end
