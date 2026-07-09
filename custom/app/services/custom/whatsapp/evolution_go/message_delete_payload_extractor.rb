# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor
  DELETE_EVENTS = %w[MESSAGE_DELETE MESSAGES_DELETE DELETE].freeze
  REVOKE_TYPES = [0, '0', 'REVOKE', 'revoke', 'PROTOCOL_MESSAGE_TYPE_REVOKE'].freeze

  module_function

  def delete_event?(event)
    DELETE_EVENTS.include?(event.to_s.upcase)
  end

  def extract_delete_key(data, event: nil)
    return extract_explicit_delete_key(data) if delete_event?(event)

    extract_revoke_key(data)
  end

  def extract_explicit_delete_key(data)
    payload = (data || {}).with_indifferent_access
    key = payload[:key] || payload
    normalize_key(key)
  end

  def extract_revoke_key(data)
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    message = (canonical[:message] || canonical['message'] || {}).with_indifferent_access
    protocol = message[:protocolMessage]
    return if protocol.blank?

    protocol = protocol.with_indifferent_access
    return unless revoke_type?(protocol[:type])

    normalize_key(protocol[:key])
  end

  def revoke_type?(value)
    REVOKE_TYPES.include?(value) || value.to_s.upcase == 'REVOKE'
  end

  def normalize_key(key)
    return if key.blank?

    key = key.with_indifferent_access
    id = Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(key, 'id', 'ID', 'Id')
    return if id.blank?

    {
      id: id,
      remoteJid: Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(key, 'remoteJid', 'remoteJID', 'RemoteJid'),
      fromMe: ActiveModel::Type::Boolean.new.cast(
        Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(key, 'fromMe', 'FromMe')
      ),
      participant: Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(key, 'participant', 'Participant')
    }.compact
  end
end
