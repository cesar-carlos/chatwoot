# frozen_string_literal: true

# Syncs WhatsApp messages sent from the connected phone (Baileys fromMe UPSERT)
# as outgoing Chatwoot messages. Skips duplicates when Chatwoot already has source_id.
class Custom::Whatsapp::Evolution::PhoneOutgoingSyncService
  include Custom::Whatsapp::Evolution::OutgoingMessageHelper

  pattr_initialize [:channel!, :data!]

  def perform
    key = message_key
    return if skip_sync?(key)

    process_sync!(key)
  rescue StandardError
    # The dedup lock was already acquired in `skip_sync?` — if anything
    # below raises before the message is persisted, release it immediately
    # instead of blocking every retry for the full 1-day TTL. The DB
    # `duplicate_message?` check remains the authoritative guard, so
    # releasing early cannot cause a duplicate send/message.
    release_dedup_lock!
    raise
  end

  private

  def process_sync!(key)
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

  def inbox
    channel.inbox
  end

  def account
    channel.account
  end

  def config
    channel.provider_config || {}
  end

  def message_key
    data['key'] || data[:key] || {}
  end

  def skip_sync?(key)
    source_id = key['id'].to_s
    return true if source_id.blank?
    return true if duplicate_message?(source_id)
    return true if skip_remote_jid?(key['remoteJid'].to_s)

    return false if acquire_dedup_lock!(source_id)

    raise MutexApplicationJob::LockAcquisitionError,
          "Evolution phone outgoing dedup lock busy for source_id=#{source_id}"
  end

  # Only ever releases a lock this instance itself acquired — releasing on
  # a failed `acquire!` would delete another worker's still-active lock.
  def acquire_dedup_lock!(source_id)
    lock = Whatsapp::MessageDedupLock.new(source_id)
    return false unless lock.acquire!

    @dedup_lock = lock
    @dedup_lock_acquired = true
  end

  def release_dedup_lock!
    return unless @dedup_lock_acquired

    @dedup_lock.release!
    @dedup_lock_acquired = false
  end

  def duplicate_message?(source_id)
    return true if inbox.messages.exists?(source_id: source_id)
    return true if secondary_source_id_exists?(source_id)

    false
  end

  def secondary_source_id_exists?(source_id)
    inbox.messages.exists?(['content_attributes::jsonb @> ?', { evolution_secondary_source_ids: [source_id] }.to_json])
  end

  def skip_remote_jid?(remote_jid)
    Custom::Whatsapp::Evolution::RemoteJidFilter.skip_remote_jid?(remote_jid, config)
  end

  def normalizer
    Custom::Whatsapp::Webhooks::EvolutionNormalizer.new(
      channel: channel,
      envelope: { 'event' => 'MESSAGES_UPSERT', 'data' => data },
      import_mode: true
    )
  end

  def find_or_create_contact_inbox(key)
    remote_jid = key['remoteJid'].to_s
    return group_contact_inbox(remote_jid) if Custom::Whatsapp::Evolution::GroupContactService.group_jid?(remote_jid)

    direct_contact_inbox(key)
  end

  def group_contact_inbox(remote_jid)
    Custom::Whatsapp::Evolution::GroupContactService.new(
      channel: channel,
      remote_jid: remote_jid,
      push_name: data['pushName']
    ).find_or_create_contact_inbox!
  end

  def direct_contact_inbox(key)
    phone = jid_resolver.phone_from_message_key(key)
    return if phone.blank?

    source_id = jid_resolver.normalize_phone(phone)
    contact = account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    contact.name = data['pushName'].presence || contact.name || contact.phone_number
    contact.save!

    ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: source_id).perform
  end

  def create_outgoing_message!(contact_inbox, key, content)
    conversation = resolve_conversation(contact_inbox)
    timestamp = message_timestamp(data['messageTimestamp'])
    conversation.messages.create!(outgoing_message_attributes(key, content, timestamp))
  end

  def resolve_conversation(contact_inbox)
    Conversations::Resolver.new(
      inbox: inbox,
      contact_inbox: contact_inbox,
      conversation_params: {
        account_id: account.id,
        inbox_id: inbox.id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id
      }
    ).perform
  end

  def outgoing_message_attributes(key, content, timestamp)
    {
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
    }
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(config)
  end
end
