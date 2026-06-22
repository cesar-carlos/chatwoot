# frozen_string_literal: true

# Syncs WhatsApp messages sent from the connected phone (Baileys fromMe UPSERT)
# as outgoing Chatwoot messages. Skips duplicates when Chatwoot already has source_id.
class Custom::Whatsapp::Evolution::PhoneOutgoingSyncService
  pattr_initialize [:channel!, :data!]

  def perform
    key = data['key'] || data[:key] || {}
    source_id = key['id'].to_s
    return if source_id.blank?
    return if duplicate_message?(source_id)
    return unless acquire_dedup_lock!(source_id)
    return if skip_remote_jid?(key['remoteJid'].to_s)

    normalized = normalizer.perform
    message_data = normalized&.dig(:messages, 0)
    content = outgoing_content(data, message_data)
    return if content.blank? && !outgoing_media_message?(message_data)

    contact_inbox = find_or_create_contact_inbox(key)
    return if contact_inbox.blank?

    message = create_outgoing_message!(contact_inbox, key, content)
    enqueue_outgoing_media_download!(message, message_data) if message_data.present?
    message
  end

  private

  def inbox
    channel.inbox
  end

  def account
    channel.account
  end

  def config
    channel.provider_config || {}
  end

  def acquire_dedup_lock!(source_id)
    Whatsapp::MessageDedupLock.new(source_id).acquire!
  end

  def duplicate_message?(source_id)
    inbox.messages.exists?(source_id: source_id)
  end

  def skip_remote_jid?(remote_jid)
    return true if remote_jid.blank?
    return true if remote_jid == 'status@broadcast' && config['ignore_status_broadcast'] != false
    return true if remote_jid.end_with?('@g.us') && config['groups_ignore'] != false

    Array(config['ignore_jids']).any? { |pattern| remote_jid.include?(pattern.to_s) }
  end

  def normalizer
    Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: { 'event' => 'MESSAGES_UPSERT', 'data' => data },
      import_mode: true
    )
  end

  def outgoing_content(record, message_data)
    return extract_fallback_text(record) if message_data.blank?

    message_data.dig(:text, :body) || media_caption(message_data) || extract_fallback_text(record)
  end

  def outgoing_media_message?(message_data)
    return false if message_data.blank?

    type = message_data[:type].to_s
    %w[image video audio document sticker].include?(type) && message_data[type.to_sym].present?
  end

  def media_caption(message_data)
    type = message_data[:type].to_s
    return unless %w[image video audio document sticker].include?(type)

    message_data[type.to_sym]&.dig(:caption)
  end

  def extract_fallback_text(record)
    message = record['message'] || {}
    message['conversation'] || message.dig('extendedTextMessage', 'text')
  end

  def find_or_create_contact_inbox(key)
    phone = jid_resolver.phone_from_message_key(key)
    return if phone.blank?

    source_id = jid_resolver.normalize_phone(phone)
    contact = account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = data['pushName'].presence || contact.name || contact.phone_number
    contact.save!

    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: source_id).perform
  end

  def create_outgoing_message!(contact_inbox, key, content)
    conversation = Conversations::Resolver.new(
      inbox: inbox,
      contact_inbox: contact_inbox,
      conversation_params: {
        account_id: account.id,
        inbox_id: inbox.id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id
      }
    ).perform

    timestamp = message_timestamp(data['messageTimestamp'])
    conversation.messages.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      status: :delivered,
      content: content,
      source_id: key['id'],
      content_attributes: {
        phone_sent: true,
        external_created_at: timestamp.iso8601
      },
      created_at: timestamp,
      updated_at: timestamp
    )
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

  def message_timestamp(value)
    seconds = value.to_i
    return Time.zone.at(seconds) if seconds.positive?

    Time.current
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(config)
  end
end
