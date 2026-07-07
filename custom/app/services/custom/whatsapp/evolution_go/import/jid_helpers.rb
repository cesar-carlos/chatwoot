# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::Import::JidHelpers
  private

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(runtime.config)
  end

  def skip_remote_jid?(remote_jid)
    config = runtime.config.stringify_keys
    return true if remote_jid.blank?
    return true if remote_jid.end_with?('@g.us') && config['ignore_groups'] != false
    return true if remote_jid == 'status@broadcast' && config['ignore_status'] != false

    false
  end

  def phone_from_contact_record(record)
    remote_jid = remote_jid_from_record(record)
    jid_resolver.phone_from_jid(remote_jid) || jid_resolver.phone_from_record(record)
  end

  def normalize_source_id(phone)
    jid_resolver.normalize_phone(phone)
  end

  def remote_jid_from_record(record)
    data = record.with_indifferent_access
    data[:Jid] || data[:jid] || data[:remoteJid]
  end

  def push_name_from_record(record)
    data = record.with_indifferent_access
    data[:PushName] || data[:pushName] || data[:FullName] || data[:fullName] ||
      data[:BusinessName] || data[:businessName] || data[:FirstName] || data[:firstName]
  end

  def extract_contacts_records(parsed)
    return [] if parsed.blank?

    if parsed.is_a?(Array)
      return parsed.map { |entry| entry.is_a?(Hash) ? entry.stringify_keys : entry }
    end

    data = parsed['data'] || parsed
    Array.wrap(data).map { |entry| entry.is_a?(Hash) ? entry.stringify_keys : entry }
  end
end
