# frozen_string_literal: true

class Custom::Whatsapp::Evolution::Import::ContactsImporter
  include Custom::Whatsapp::Evolution::Import::JidHelpers

  BATCH_SIZE = Custom::Whatsapp::Evolution::ImportService::BATCH_SIZE
  RATE_LIMIT_SLEEP = Custom::Whatsapp::Evolution::ImportService::RATE_LIMIT_SLEEP

  def initialize(runtime:, api_client:)
    @runtime = runtime
    @api_client = api_client
  end

  def import_batch!
    page = runtime.cursor[:contacts_page].to_i
    page = 1 if page < 1

    response = api_client.find_contacts(page: page, offset: BATCH_SIZE)
    Custom::Whatsapp::Evolution::ApiClient.raise_unless_success!(
      response,
      'Failed to fetch Evolution contacts'
    )
    contacts = extract_contacts_records(response.parsed_response)
    if contacts.blank?
      advance_to_messages_phase!
      return
    end

    import_contacts_page(contacts, page)
    advance_to_messages_phase! if contacts.size < BATCH_SIZE
  end

  private

  attr_reader :runtime, :api_client

  def import_contacts_page(contacts, page)
    remote_jids = runtime.cursor[:remote_jids] || []
    contacts.each do |record|
      next unless record.is_a?(Hash)

      remote_jids << record['remoteJid'] if record['remoteJid'].present?
      import_contact_record(record)
    end

    runtime.update_stats!(contacts_imported: contacts.size)
    runtime.persist_cursor!(
      'contacts_page' => page + 1,
      'remote_jids' => remote_jids.uniq,
      'phase' => 'contacts'
    )
  end

  def import_contact_record(record)
    remote_jid = record['remoteJid'].to_s
    return if skip_remote_jid?(remote_jid)

    source_id = normalize_source_id(phone_from_contact_record(record))
    return if source_id.blank?

    contact = upsert_contact(record, remote_jid)
    link_contact_inbox(contact, source_id)
    enqueue_contact_enrichment(contact, remote_jid, record['pushName'], record['profilePicUrl'])
  end

  def upsert_contact(record, remote_jid)
    phone = phone_from_contact_record(record)
    contact = runtime.account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = record['pushName'].presence || contact.name || contact.phone_number
    lid = jid_resolver.lid_identifier_for(remote_jid)
    contact.identifier = lid if lid.present?
    contact.additional_attributes = (contact.additional_attributes || {}).merge(
      Custom::Whatsapp::Evolution::ContactEnrichmentService::EVOLUTION_REMOTE_JID_KEY => remote_jid
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

  def enqueue_contact_enrichment(contact, remote_jid, push_name, profile_pic_url)
    return unless Custom::Whatsapp::Evolution::ContactEnrichmentService.should_enqueue?(
      contact: contact,
      remote_jid: remote_jid,
      push_name: push_name,
      profile_pic_url: profile_pic_url
    )

    Custom::Whatsapp::Evolution::ContactEnrichmentJob.perform_later(
      runtime.channel.id,
      contact.id,
      {
        remote_jid: remote_jid,
        push_name: push_name,
        profile_pic_url: profile_pic_url
      }.compact
    )
  end

  def advance_to_messages_phase!
    if runtime.import_messages?
      remote_jids = runtime.cursor[:remote_jids].presence || remote_jids_collector.collect!
      runtime.persist_cursor!(
        'phase' => 'messages',
        'message_jid_index' => 0,
        'message_page' => 1,
        'remote_jids' => remote_jids
      )
    else
      runtime.mark_completed!
    end
  end

  def remote_jids_collector
    @remote_jids_collector ||= Custom::Whatsapp::Evolution::Import::RemoteJidsCollector.new(
      runtime: runtime,
      api_client: api_client
    )
  end

  def extract_contacts_records(parsed)
    return Array.wrap(parsed) unless parsed.is_a?(Hash)

    Array.wrap(parsed.dig('contacts', 'records') || parsed['records'] || parsed['contacts'] || parsed)
  end
end
