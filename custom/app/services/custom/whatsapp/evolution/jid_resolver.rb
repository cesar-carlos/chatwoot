# frozen_string_literal: true

class Custom::Whatsapp::Evolution::JidResolver
  def initialize(config = {})
    @config = (config || {}).stringify_keys
  end

  def phone_from_record(record)
    record = record.with_indifferent_access
    remote_jid = record[:remoteJid].to_s
    return if remote_jid.blank?

    phone_from_jid(resolve_contact_jid(record, remote_jid))
  end

  def resolve_contact_jid(record, remote_jid = nil)
    record = record.with_indifferent_access
    remote_jid = remote_jid.presence || record[:remoteJid].to_s
    alt = record[:remoteJidAlt].to_s
    return alt if alt.present? && lid_addressing?(remote_jid, record[:addressingMode])

    remote_jid
  end

  def phone_from_message_key(key)
    key = key.with_indifferent_access
    phone_from_jid(resolve_message_jid(key))
  end

  def resolve_message_jid(key)
    key = key.with_indifferent_access
    remote_jid = key[:remoteJid].to_s
    alt = key[:remoteJidAlt].to_s
    return alt if alt.present? && lid_addressing?(remote_jid, key[:addressingMode])

    remote_jid
  end

  def phone_from_jid(jid)
    jid_str = jid.to_s
    return if jid_str.end_with?('@lid')

    phone = jid_str.split('@').first.presence
    return if phone.blank?
    return unless phone.match?(/\A\d+\z/)

    normalize_phone(phone)
  end

  def normalize_phone(phone)
    normalized = phone.to_s.gsub(/\D/, '')
    return normalized unless merge_brazil_contacts? && normalized.start_with?('55')

    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(normalized)
  end

  def lid_identifier_for(remote_jid)
    remote_jid if remote_jid.to_s.end_with?('@lid')
  end

  def recipient_id_for_status(remote_jid, key = nil)
    jid = status_remote_jid(remote_jid, key)
    return group_recipient_id(jid) if group_jid?(jid)

    status_recipient_from_jid(key, remote_jid)
  end

  def group_id_from_jid(jid)
    jid.to_s.split('@').first if group_jid?(jid)
  end

  private

  attr_reader :config

  def group_jid?(jid)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(jid.to_s)
  end

  def group_recipient_id(jid)
    Custom::Whatsapp::Evolution::GroupContactService.source_id_for(jid)
  end

  def status_remote_jid(remote_jid, key)
    key = key.with_indifferent_access if key.present?
    key.present? ? (key[:remoteJid] || remote_jid) : remote_jid
  end

  def status_recipient_from_jid(key, remote_jid)
    if key.present?
      phone_from_message_key(key) || group_id_from_jid(key[:remoteJid] || remote_jid)
    else
      phone_from_jid(resolve_message_jid({ remoteJid: remote_jid })) || group_id_from_jid(remote_jid)
    end
  end

  def lid_addressing?(remote_jid, addressing_mode)
    remote_jid.to_s.end_with?('@lid') || addressing_mode.to_s == 'lid'
  end

  def merge_brazil_contacts?
    ActiveModel::Type::Boolean.new.cast(config['merge_brazil_contacts'])
  end
end
