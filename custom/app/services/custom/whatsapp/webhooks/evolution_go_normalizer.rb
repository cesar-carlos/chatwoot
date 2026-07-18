# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionGoNormalizer
  include Custom::Whatsapp::Webhooks::EvolutionGo::PayloadBuilders
  include Custom::Whatsapp::Webhooks::EvolutionGo::StatusNormalizer

  attr_reader :channel, :envelope

  def initialize(channel, envelope)
    @channel = channel
    @envelope = envelope
  end

  def perform
    envelope_data = envelope.with_indifferent_access
    return unless envelope_data[:event].to_s.upcase == 'MESSAGE'

    data = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(envelope_data[:data])
    return if data.blank?
    return if filtered?(data)

    normalize_message(data)
  end

  private

  def config
    channel.provider_config || Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS
  end

  def filtered?(data)
    key = data['key'] || data[:key] || {}
    remote_jid = extract_remote_jid(key)
    return true if echo_filtered?(key)
    return true if group_filtered?(remote_jid)

    status_broadcast?(remote_jid)
  end

  def echo_filtered?(key)
    from_me?(key) && ignore_from_me_echo?
  end

  def group_filtered?(remote_jid)
    ignore_groups? && group_jid?(remote_jid)
  end

  def normalize_message(data)
    key = data['key'] || data[:key] || {}
    message_body = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.unwrap_nested_message(
      data['message'] || data[:message] || {}
    )
    return if secret_encrypted_only?(message_body)

    wa_id = resolve_wa_id(key)
    message_hash = build_inbound_message_hash(data, key, wa_id, message_body)
    return if message_hash.blank?

    enrich_inbound_message_hash!(message_hash, data, key, message_body)
    wrap_inbound_contacts(key, data, wa_id, message_hash)
  end

  def build_inbound_message_hash(data, key, wa_id, message_body)
    return build_unavailable_message_hash(data, wa_id, key) if unavailable_payload?(data)

    message_body = (message_body || {}).with_indifferent_access
    # Reactions are handled by MessageReactionSyncService — never create a text bubble.
    return nil if message_body['reactionMessage'].present?

    message_type = map_message_type(message_body)
    build_message_hash(data.merge('message' => message_body), wa_id, message_type, key)
  end

  def enrich_inbound_message_hash!(message_hash, data, key, message_body)
    add_reply_context!(message_hash, data.merge('message' => message_body)) unless unavailable_payload?(data)
    attach_participant_metadata!(message_hash, key)
  end

  def wrap_inbound_contacts(key, data, wa_id, message_hash)
    {
      contacts: [{ profile: { name: group_contact_name(key, data) }, wa_id: wa_id }],
      messages: [message_hash]
    }
  end

  def unavailable_payload?(data)
    ActiveModel::Type::Boolean.new.cast(data['is_unavailable'] || data[:is_unavailable])
  end

  def build_unavailable_message_hash(data, wa_id, key)
    return nil if wa_id.blank?

    unavailable_type = (data['unavailable_type'] || data[:unavailable_type]).to_s.presence || 'unknown'
    Rails.logger.info(
      "[EVOLUTION_GO] unavailable inbound message type=#{unavailable_type} id=#{key['id'] || key[:id]}"
    )

    {
      from: wa_id,
      id: key['id'] || key[:id],
      timestamp: (data['messageTimestamp'] || data[:messageTimestamp]).to_s,
      type: 'unsupported',
      evolution_go_remote_jid: group_remote_jid(key, wa_id),
      evolution_go_unavailable_type: unavailable_type
    }.compact
  end

  def secret_encrypted_only?(message)
    message = (message || {}).with_indifferent_access
    return false if message[:secretEncryptedMessage].blank?

    substantive = message.keys.map(&:to_s) - %w[messageContextInfo secretEncryptedMessage]
    substantive.empty?
  end

  def resolve_wa_id(key)
    remote_jid = extract_remote_jid(key)
    return group_wa_id(remote_jid) if group_jid?(remote_jid)

    phone_from_jid(remote_jid)
  end

  def group_wa_id(remote_jid)
    Custom::Whatsapp::Evolution::GroupContactService.source_id_for(remote_jid)
  end

  def group_contact_name(key, data)
    remote_jid = extract_remote_jid(key)
    return data['pushName'].to_s unless group_jid?(remote_jid)

    Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel)
                                                     .display_name(remote_jid, fallback: data['pushName'])
  end

  def attach_participant_metadata!(message_hash, key)
    participant = participant_jid_from_key(key)
    return if participant.blank?

    message_hash[:evolution_go_participant_jid] = participant
  end

  def participant_jid_from_key(key)
    key = key.with_indifferent_access
    participant = key[:participant].to_s.presence
    return participant if participant.present? && !group_jid?(participant)

    nil
  end

  def extract_remote_jid(key)
    jid_resolver.resolve_message_jid(key.with_indifferent_access)
  end

  def phone_from_jid(jid)
    jid_resolver.phone_from_jid(jid)
  end

  def from_me?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def ignore_from_me_echo?
    ActiveModel::Type::Boolean.new.cast(config['ignore_from_me_echo'])
  end

  def ignore_groups?
    ActiveModel::Type::Boolean.new.cast(config['ignore_groups'])
  end

  def group_jid?(remote_jid)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(remote_jid)
  end

  def status_broadcast?(remote_jid)
    return false unless ignore_status?

    remote_jid.to_s == 'status@broadcast'
  end

  def ignore_status?
    ActiveModel::Type::Boolean.new.cast(config['ignore_status'])
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(config)
  end
end
