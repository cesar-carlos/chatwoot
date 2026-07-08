# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::Import::ContactsImporter
  include Custom::Whatsapp::EvolutionGo::Import::JidHelpers

  BATCH_SIZE = Custom::Whatsapp::EvolutionGo::ImportService::BATCH_SIZE
  RATE_LIMIT_SLEEP = Custom::Whatsapp::EvolutionGo::ImportService::RATE_LIMIT_SLEEP

  def initialize(runtime:, api_client:)
    @runtime = runtime
    @api_client = api_client
  end

  def import_batch!
    contacts = fetch_contacts_list
    if contacts.blank?
      advance_to_messages_phase!
      return
    end

    offset = runtime.cursor[:contacts_offset].to_i
    batch = contacts.slice(offset, BATCH_SIZE)
    if batch.blank?
      advance_to_messages_phase!
      return
    end

    import_contacts_batch(batch, offset, contacts.size)
    sleep(RATE_LIMIT_SLEEP)
  end

  private

  attr_reader :runtime, :api_client

  def fetch_contacts_list
    Rails.cache.fetch(runtime.contacts_cache_key, expires_in: 30.minutes) do
      response = api_client.user_contacts
      Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(
        response,
        'Failed to fetch Evolution Go contacts'
      )
      extract_contacts_records(response.parsed_response)
    end
  end

  def import_contacts_batch(contacts, offset, total_count)
    remote_jids = load_remote_jids
    contacts.each do |record|
      next unless record.is_a?(Hash)

      remote_jid = remote_jid_from_record(record)
      remote_jids << remote_jid if remote_jid.present?
      import_contact_record(record, remote_jid)
    end

    save_remote_jids!(remote_jids.uniq)
    runtime.update_stats!(contacts_imported: contacts.size)
    next_offset = offset + contacts.size
    if next_offset >= total_count
      advance_to_messages_phase!
      return
    end

    runtime.persist_cursor!(
      'contacts_offset' => next_offset,
      'phase' => 'contacts'
    )
  end

  def load_remote_jids
    stored = ::Redis::Alfred.get(remote_jids_redis_key)
    return [] if stored.blank?

    JSON.parse(stored)
  rescue JSON::ParserError
    []
  end

  def save_remote_jids!(jids)
    ::Redis::Alfred.set(remote_jids_redis_key, jids.to_json, ex: 7.days.to_i)
  end

  def remote_jids_redis_key
    format(Redis::RedisKeys::EVOLUTION_GO_IMPORT_REMOTE_JIDS, channel_id: runtime.channel.id)
  end

  def import_contact_record(record, remote_jid)
    return if skip_remote_jid?(remote_jid)

    source_id = normalize_source_id(phone_from_contact_record(record))
    return if source_id.blank?

    contact = upsert_contact(record, remote_jid)
    link_contact_inbox(contact, source_id)
    enqueue_contact_enrichment(contact, remote_jid, push_name_from_record(record))
  end

  def upsert_contact(record, remote_jid)
    phone = phone_from_contact_record(record)
    contact = runtime.account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    name = push_name_from_record(record).presence || contact.name || contact.phone_number
    contact.name = name
    lid = jid_resolver.lid_identifier_for(remote_jid)
    contact.identifier = lid if lid.present?
    contact.additional_attributes = (contact.additional_attributes || {}).merge(
      Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY => remote_jid
    )
    contact.save!
    contact
  end

  def link_contact_inbox(contact, source_id)
    ContactInboxBuilder.new(
      contact: contact,
      inbox: runtime.inbox,
      source_id: source_id
    ).perform
  end

  def enqueue_contact_enrichment(contact, remote_jid, push_name)
    return unless Custom::Whatsapp::EvolutionGo::ContactEnrichmentService.should_enqueue?(
      contact: contact,
      remote_jid: remote_jid,
      push_name: push_name,
      force: true
    )

    Custom::Whatsapp::EvolutionGo::ContactEnrichmentJob.perform_later(
      runtime.channel.id,
      contact.id,
      {
        remote_jid: remote_jid,
        push_name: push_name,
        force: true
      }.compact
    )
  end

  def advance_to_messages_phase!
    if runtime.import_messages?
      remote_jids = load_remote_jids
      runtime.persist_cursor!(
        'phase' => 'messages',
        'message_jid_index' => 0,
        'message_page' => 1
      )
      save_remote_jids!(remote_jids) if remote_jids.present?
    else
      runtime.mark_completed!
      ::Redis::Alfred.delete(remote_jids_redis_key)
    end
  end
end
