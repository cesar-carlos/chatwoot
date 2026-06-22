# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- contact resolution + incoming/outgoing history paths
class Custom::Whatsapp::Evolution::Import::MessagesImporter
  include Custom::Whatsapp::Evolution::Import::JidHelpers

  BATCH_SIZE = Custom::Whatsapp::Evolution::ImportService::BATCH_SIZE

  def initialize(runtime:, api_client:, channel:)
    @runtime = runtime
    @api_client = api_client
    @channel = channel
  end

  def import_batch!
    remote_jids = Array.wrap(runtime.cursor[:remote_jids])
    if remote_jids.blank?
      remote_jids = remote_jids_collector.collect!
      return runtime.mark_completed! if remote_jids.blank?

      runtime.persist_cursor!('remote_jids' => remote_jids)
    end

    jid_index, page = message_cursor
    return runtime.mark_completed! if jid_index >= remote_jids.size

    import_page(remote_jids, jid_index, page)
  end

  private

  attr_reader :runtime, :api_client, :channel

  def message_cursor
    jid_index = runtime.cursor[:message_jid_index].to_i
    page = runtime.cursor[:message_page].to_i
    page = 1 if page < 1
    [jid_index, page]
  end

  def import_page(remote_jids, jid_index, page)
    remote_jid = remote_jids[jid_index]
    response = api_client.find_messages(page: page, offset: BATCH_SIZE, where: messages_where(remote_jid))
    Custom::Whatsapp::Evolution::ApiClient.raise_unless_success!(
      response,
      'Failed to fetch Evolution messages for import'
    )
    parsed = response.parsed_response || {}
    records = Array.wrap(parsed.dig('messages', 'records'))

    if records.blank?
      advance_jid_cursor!(remote_jids, jid_index)
      return
    end

    records.each { |record| import_message_record(record) }
    advance_page_cursor!(parsed, jid_index, page, remote_jids.size)
  end

  def advance_jid_cursor!(remote_jids, jid_index)
    runtime.persist_cursor!(
      'message_jid_index' => jid_index + 1,
      'message_page' => 1,
      'phase' => 'messages'
    )
    runtime.mark_completed! if jid_index + 1 >= remote_jids.size
  end

  def advance_page_cursor!(parsed, jid_index, page, jid_count)
    total_pages = parsed.dig('messages', 'pages').to_i
    if page < total_pages
      runtime.persist_cursor!('message_page' => page + 1, 'phase' => 'messages')
      return
    end

    runtime.persist_cursor!(
      'message_jid_index' => jid_index + 1,
      'message_page' => 1,
      'phase' => 'messages'
    )
    runtime.mark_completed! if jid_index + 1 >= jid_count
  end

  def import_message_record(record)
    key = record['key'] || {}
    source_id = key['id'].to_s
    return if source_id.blank?
    return if Message.exists?(source_id: source_id, inbox_id: runtime.inbox.id)

    if key['fromMe']
      import_outgoing_record(record)
    else
      import_incoming_record(record)
    end
  end

  def import_incoming_record(record)
    envelope = { 'event' => 'MESSAGES_UPSERT', 'data' => record }
    normalized = normalizer(envelope).perform
    return if normalized.blank?

    Whatsapp::IncomingMessageService.new(
      inbox: runtime.inbox,
      params: normalized.merge(phone_number: channel.phone_number)
    ).perform

    stamp_imported_message!(record.dig('key', 'id'), record['messageTimestamp'])
  end

  def import_outgoing_record(record)
    envelope = { 'event' => 'MESSAGES_UPSERT', 'data' => record }
    normalized = normalizer(envelope).perform
    message_data = normalized&.dig(:messages, 0)
    return if message_data.blank?

    key = record['key'] || {}
    content = outgoing_content(record, message_data)
    return if content.blank? && !outgoing_media_message?(message_data)

    contact_inbox = find_or_create_contact_inbox_for_key(key, record['pushName'])
    return if contact_inbox.blank?

    message = create_outgoing_message!(
      contact_inbox,
      key,
      content,
      record['messageTimestamp']
    )
    enqueue_outgoing_media_download!(message, message_data)
    runtime.increment_stat!(:messages_imported)
  end

  def outgoing_content(record, message_data = nil)
    message_data ||= begin
      envelope = { 'event' => 'MESSAGES_UPSERT', 'data' => record }
      normalizer(envelope).perform&.dig(:messages, 0)
    end
    return extract_fallback_text(record) if message_data.blank?

    message_data.dig(:text, :body) || media_caption(message_data) || extract_fallback_text(record)
  end

  def outgoing_media_message?(message_data)
    type = message_data[:type].to_s
    %w[image video audio document sticker].include?(type) && message_data[type.to_sym].present?
  end

  def media_caption(message_data)
    type = message_data[:type].to_s
    return unless %w[image video audio document sticker].include?(type)

    message_data[type.to_sym]&.dig(:caption)
  end

  def enqueue_outgoing_media_download!(message, message_data)
    return unless outgoing_media_message?(message_data)

    type = message_data[:type].to_s
    attachment_payload = message_data[type.to_sym]
    return if attachment_payload.blank?

    Custom::Whatsapp::Evolution::MediaDownloadJob.perform_later(
      channel.id,
      message.id,
      attachment_payload.deep_stringify_keys,
      type
    )
  end

  def create_outgoing_message!(contact_inbox, key, content, raw_timestamp)
    conversation = find_or_create_conversation(contact_inbox)
    timestamp = message_timestamp(raw_timestamp)
    conversation.messages.create!(outgoing_message_attrs(key, content, timestamp))
  end

  def find_or_create_conversation(contact_inbox)
    Conversations::Resolver.new(
      inbox: runtime.inbox,
      contact_inbox: contact_inbox,
      conversation_params: conversation_params(contact_inbox)
    ).perform
  end

  def outgoing_message_attrs(key, content, timestamp)
    {
      account_id: runtime.account.id,
      inbox_id: runtime.inbox.id,
      message_type: :outgoing,
      status: :delivered,
      content: content,
      source_id: key['id'],
      content_attributes: {
        history_import: true,
        external_created_at: timestamp.iso8601
      },
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  def conversation_params(contact_inbox)
    {
      account_id: runtime.account.id,
      inbox_id: runtime.inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    }
  end

  def find_or_create_contact_inbox_for_key(key, push_name)
    phone = phone_from_message_key(key)
    return if phone.blank?

    source_id = normalize_source_id(phone)
    contact = runtime.account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = push_name.presence || contact.name || contact.phone_number
    contact.save!

    ContactInboxBuilder.new(contact: contact, inbox: runtime.inbox, source_id: source_id).perform
  end

  def stamp_imported_message!(source_id, raw_timestamp)
    message = Message.find_by(inbox_id: runtime.inbox.id, source_id: source_id)
    return if message.blank?

    timestamp = message_timestamp(raw_timestamp)
    backdate_imported_message!(message, timestamp)
    runtime.increment_stat!(:messages_imported)
  end

  def backdate_imported_message!(message, timestamp)
    attrs = (message.content_attributes || {}).merge(
      history_import: true,
      external_created_at: timestamp.iso8601
    )
    message.update_columns( # rubocop:disable Rails/SkipsModelValidations -- skip callbacks on history import
      content_attributes: attrs,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def messages_where(remote_jid)
    {
      key: { remoteJid: remote_jid },
      messageTimestamp: {
        gte: days_limit.ago.utc.iso8601(3),
        lte: Time.current.utc.iso8601(3)
      }
    }
  end

  def days_limit
    runtime.config.fetch('days_limit_import_messages', 7).to_i.days
  end

  def extract_fallback_text(record)
    message = record['message'] || {}
    message['conversation'] || message.dig('extendedTextMessage', 'text')
  end

  def message_timestamp(value)
    seconds = value.to_i
    return Time.zone.at(seconds) if seconds.positive?

    Time.current
  end

  def normalizer(envelope)
    Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: envelope,
      import_mode: true
    )
  end

  def remote_jids_collector
    @remote_jids_collector ||= Custom::Whatsapp::Evolution::Import::RemoteJidsCollector.new(
      runtime: runtime,
      api_client: api_client
    )
  end
end
# rubocop:enable Metrics/ClassLength
