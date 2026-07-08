# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
class Custom::Whatsapp::EvolutionGo::PhoneOutgoingSyncService
  pattr_initialize [:channel!, :data!]

  def perform
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    key = canonical['key'] || canonical[:key] || {}
    return if skip_sync?(key)

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
    content = message_data&.dig(:text, :body) || message_data&.dig('text', 'body')
    return if content.blank? && message_data.blank?

    contact_inbox = find_or_create_contact_inbox(key)
    return if contact_inbox.blank?

    create_outgoing_message!(contact_inbox, key, content)
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
    return true if group_jid?(key['remoteJid'].to_s) && ignore_groups?

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
    remote_jid = key['remoteJid'].to_s
    if group_jid?(remote_jid) && !ignore_groups?
      return Custom::Whatsapp::Evolution::GroupContactService.new(
        channel: channel,
        remote_jid: remote_jid,
        push_name: data['pushName'] || data[:pushName]
      ).find_or_create_contact_inbox!
    end

    phone = jid_resolver.phone_from_message_key(key)
    return if phone.blank?

    source_id = jid_resolver.normalize_phone(phone)
    contact = account.contacts.find_or_initialize_by(phone_number: "+#{phone}")
    push_name = data['pushName'] || data[:pushName]
    contact.name = push_name.presence || contact.name || contact.phone_number
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

    timestamp = Time.zone.at((data['messageTimestamp'] || data[:messageTimestamp] || Time.current.to_i).to_i)
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

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(config)
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
