# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionNormalizer
  include Custom::Whatsapp::Webhooks::Evolution::MessageFilters
  include Custom::Whatsapp::Webhooks::Evolution::StatusMapper
  include Custom::Whatsapp::Webhooks::Evolution::PayloadBuilders

  attr_reader :channel, :envelope, :import_mode

  def initialize(channel:, envelope:, import_mode: false)
    @channel = channel
    @envelope = envelope
    @import_mode = import_mode
  end

  def perform
    envelope = @envelope.with_indifferent_access
    return nil unless envelope[:event].in?(%w[MESSAGES_UPSERT MESSAGES_UPDATE])

    data = envelope[:data]
    return nil if data.blank?

    return normalize_status(data) if envelope[:event] == 'MESSAGES_UPDATE'

    normalize_message(data)
  end

  private

  def config
    channel.provider_config || Custom::Whatsapp::Evolution::ProviderConfigDefaults::DEFAULTS
  end

  def normalize_message(data)
    data = unwrap_ephemeral_message(data)
    return nil if ignore_message?(data)

    key = data['key'] || data[:key] || {}
    wa_id = resolve_wa_id(key)
    message_type = map_message_type(data)
    message_hash = build_message_hash(data, wa_id, message_type, key)
    return nil if message_hash.blank?

    add_reply_context!(message_hash, data)
    attach_participant_metadata!(message_hash, key)

    contact_name = group_contact_name(key, data)
    {
      contacts: [{ profile: { name: contact_name }, wa_id: wa_id }],
      messages: [message_hash]
    }
  end

  def resolve_wa_id(key)
    key ||= {}
    remote_jid = key['remoteJid'].to_s
    return group_wa_id(remote_jid) if group_jid?(remote_jid)

    jid_resolver.phone_from_message_key(key)
  end

  def group_wa_id(remote_jid)
    Custom::Whatsapp::Evolution::GroupContactService.source_id_for(remote_jid)
  end

  def group_contact_name(key, data)
    return data['pushName'].to_s unless group_jid?(key['remoteJid'].to_s)

    Custom::Whatsapp::Evolution::GroupMetadataService.new(channel: channel)
                                                     .display_name(key['remoteJid'].to_s, fallback: data['pushName'])
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(config)
  end

  def attach_participant_metadata!(message_hash, key)
    participant = key['participant'].to_s.presence
    return if participant.blank?

    message_hash[:evolution_participant_jid] = participant
  end
end
