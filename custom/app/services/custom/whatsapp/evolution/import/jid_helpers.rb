# frozen_string_literal: true

module Custom::Whatsapp::Evolution::Import::JidHelpers
  private

  # Includers that don't track import `runtime` (e.g. ContactsSyncService,
  # which reacts to live webhooks instead of a batch import) must override
  # this to point at their own provider config source.
  def jid_config
    runtime.config
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(jid_config)
  end

  def skip_remote_jid?(remote_jid)
    Custom::Whatsapp::Evolution::RemoteJidFilter.skip_remote_jid?(remote_jid, jid_config)
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
    ActiveModel::Type::Boolean.new.cast(jid_config['merge_brazil_contacts'])
  end

  # The Evolution API returns either a flat array of records or a nested
  # shape (e.g. `{ contacts: { records: [...] } }` / `{ records: [...] }` /
  # `{ contacts: [...] }`) depending on the endpoint/version. Every caller
  # that walks a `findContacts`/`findChats`-style response must go through
  # this helper so the two shapes stay in sync.
  def extract_records(parsed, primary_key)
    return Array.wrap(parsed) unless parsed.is_a?(Hash)

    Array.wrap(parsed.dig(primary_key, 'records') || parsed['records'] || parsed[primary_key] || parsed)
  end
end
