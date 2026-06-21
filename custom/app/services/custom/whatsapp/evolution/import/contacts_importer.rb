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
    contacts = Array.wrap(response.parsed_response)
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

    phone = phone_from_jid(remote_jid)
    return if phone.blank?

    source_id = normalize_source_id(phone)
    return if source_id.blank?

    contact = runtime.account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = record['pushName'].presence || contact.name || contact.phone_number
    contact.save!

    ContactInboxBuilder.new(
      contact: contact,
      inbox: runtime.inbox,
      source_id: source_id
    ).perform
  end

  def advance_to_messages_phase!
    if runtime.import_messages?
      remote_jids = runtime.cursor[:remote_jids].presence || collect_remote_jids!
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

  def collect_remote_jids!
    jids = []
    page = 1

    loop do
      response = api_client.find_contacts(page: page, offset: BATCH_SIZE)
      contacts = Array.wrap(response.parsed_response)
      break if contacts.blank?

      contacts.each do |record|
        jid = record['remoteJid'].to_s
        jids << jid if jid.present? && !skip_remote_jid?(jid)
      end

      break if contacts.size < BATCH_SIZE

      page += 1
      sleep(RATE_LIMIT_SLEEP)
    end

    jids.uniq
  end
end
