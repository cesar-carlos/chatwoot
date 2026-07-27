# frozen_string_literal: true

# Syncs WhatsApp messages sent from the connected phone (Evolution Go SEND_MESSAGE /
# MESSAGE with fromMe) as outgoing Chatwoot messages.
class Custom::Whatsapp::EvolutionGo::PhoneOutgoingSyncService
  include Custom::Whatsapp::Evolution::OutgoingMessageHelper

  pattr_initialize [:channel!, :data!]

  def perform
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    key = canonical['key'] || canonical[:key] || {}
    return if skip_sync?(key)

    if protocol_only_message?(canonical)
      release_dedup_lock!
      return
    end

    process_sync!(canonical, key)
  rescue StandardError
    release_dedup_lock!
    raise
  end

  private

  def process_sync!(canonical, key)
    normalized = Custom::Whatsapp::Webhooks::EvolutionGoNormalizer.new(
      channel,
      { 'event' => 'MESSAGE', 'data' => canonical }
    ).perform
    message_data = normalized&.dig(:messages, 0)
    content = outgoing_content(canonical, message_data)
    if content.blank? && !outgoing_media_message?(message_data)
      Rails.logger.warn(
        "[EVOLUTION_GO] phone-outgoing blank content: source=#{key['id'] || key[:id]} " \
        "jid=#{key['remoteJid'] || key[:remoteJid]}"
      )
      release_dedup_lock!
      return
    end

    contact_inbox = find_or_create_contact_inbox(key)
    if contact_inbox.blank?
      release_dedup_lock!
      return
    end

    message = create_outgoing_message!(contact_inbox, key, content, canonical)
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

  def skip_sync?(key)
    source_id = key['id'].to_s
    return true if source_id.blank?
    return true if duplicate_message?(source_id)

    if group_jid?(key['remoteJid'].to_s) && ignore_groups?
      Rails.logger.info("[EVOLUTION_GO] phone-outgoing skipped: group ignored source=#{source_id}")
      return true
    end

    return false if acquire_dedup_lock!(source_id)

    raise MutexApplicationJob::LockAcquisitionError,
          "Evolution Go phone outgoing dedup lock busy for source_id=#{source_id}"
  end

  def duplicate_message?(source_id)
    inbox.messages.exists?(source_id: source_id)
  end

  def group_jid?(remote_jid)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(remote_jid)
  end

  def ignore_groups?
    ActiveModel::Type::Boolean.new.cast(config['ignore_groups'])
  end

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

  def find_or_create_contact_inbox(key)
    key_data = key.with_indifferent_access
    remote_jid = key_data['remoteJid'].to_s
    if group_jid?(remote_jid) && !ignore_groups?
      return Custom::Whatsapp::Evolution::GroupContactService.new(
        channel: channel,
        remote_jid: remote_jid,
        push_name: nil
      ).find_or_create_contact_inbox!
    end

    Custom::Whatsapp::EvolutionGo::PeerContactInboxResolver.new(channel: channel, key: key_data).find_or_create!
  end

  def create_outgoing_message!(contact_inbox, key, content, canonical)
    conversation = resolve_outgoing_conversation(contact_inbox)
    timestamp = outgoing_message_timestamp(canonical)
    remote_jid = jid_resolver.resolve_message_jid(key.with_indifferent_access)

    conversation.messages.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      status: :delivered,
      content: content,
      source_id: key['id'],
      content_attributes: outgoing_content_attributes(timestamp, remote_jid),
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def resolve_outgoing_conversation(contact_inbox)
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

  def outgoing_message_timestamp(canonical)
    message_timestamp(
      canonical['messageTimestamp'] || canonical[:messageTimestamp] ||
        data['messageTimestamp'] || data[:messageTimestamp]
    )
  end

  def outgoing_content_attributes(timestamp, remote_jid)
    {
      :phone_sent => true,
      :external_created_at => timestamp.iso8601,
      Custom::Whatsapp::EvolutionGo::ContactEnrichmentService::EVOLUTION_GO_REMOTE_JID_KEY => remote_jid
    }.compact
  end

  def enqueue_outgoing_media_download!(message, message_data)
    return unless outgoing_media_message?(message_data)

    data = message_data.with_indifferent_access
    type = data[:type].to_s
    attachment_payload = data[type]
    return if attachment_payload.blank?

    Custom::Whatsapp::EvolutionGo::MediaDownloadJob.perform_later(
      channel.id,
      message.id,
      attachment_payload.deep_stringify_keys,
      type
    )
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(config)
  end

  def protocol_only_message?(canonical)
    message = (canonical['message'] || canonical[:message] || {}).with_indifferent_access
    return false if message.blank?
    return true if secret_encrypted_edit_only?(message)

    protocol_mutation_only?(message)
  end

  def protocol_mutation_only?(message)
    substantive_keys = message.keys.map(&:to_s) - %w[messageContextInfo]
    return false unless substantive_keys == %w[protocolMessage]

    protocol = message[:protocolMessage].to_h.with_indifferent_access
    Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.revoke_type?(protocol[:type]) ||
      Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.revoke_type?(protocol[:typeName]) ||
      Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor.edit_type?(protocol[:type]) ||
      Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor.edit_type?(protocol[:typeName])
  end

  def secret_encrypted_edit_only?(message)
    return false if message[:secretEncryptedMessage].blank?

    substantive = message.keys.map(&:to_s) - %w[messageContextInfo secretEncryptedMessage]
    substantive.empty?
  end
end
