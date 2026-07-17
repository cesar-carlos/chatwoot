# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor
  EDIT_EVENTS = %w[MESSAGES_EDITED MESSAGE_EDIT SEND_MESSAGE_UPDATE].freeze
  EDIT_TYPES = [
    14, '14',
    'EDIT', 'edit',
    'MESSAGE_EDIT', 'message_edit',
    'PROTOCOL_MESSAGE_TYPE_MESSAGE_EDIT'
  ].freeze
  # WhatsApp Edit counter: "1" = message edit. Other non-zero values (e.g. "7" on revoke) are not edits.
  EDIT_INFO_VALUES = %w[1 true True TRUE].freeze

  module_function

  def edit_event?(event)
    EDIT_EVENTS.include?(event.to_s.upcase)
  end

  def extract_edit_payload(data, event: nil)
    return extract_explicit_edit_payload(data) if edit_event?(event)

    extract_protocol_edit_payload(data) || extract_secret_edit_payload(data)
  end

  def extract_explicit_edit_payload(data)
    payload = (data || {}).with_indifferent_access
    key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.normalize_key(payload[:key])
    return if key.blank?

    body = extract_edited_body(payload)
    return if body.blank?

    { key: key, edited_body: body }
  end

  def extract_protocol_edit_payload(data)
    raw = (data || {}).with_indifferent_access
    message = canonical_message(data)
    protocol = message[:protocolMessage]
    return if protocol.blank?

    protocol = protocol.with_indifferent_access
    return if protocol_revoke?(protocol, raw)
    return unless protocol_edit_signal?(protocol, raw)

    key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.normalize_key(protocol[:key])
    return if key.blank?

    body = extract_edited_body(protocol)
    return if body.blank?

    { key: key, edited_body: body }
  end

  # Evolution Go (whatsmeow) often delivers client edits as Info.Edit + secretEncryptedMessage
  # instead of protocolMessage/editedMessage. Encrypted payloads have no plaintext body —
  # still return a marker so the job can short-circuit and avoid "[Unsupported message type]".
  def extract_secret_edit_payload(data)
    raw = (data || {}).with_indifferent_access
    info = (raw[:Info] || raw[:info] || {}).with_indifferent_access
    message = secret_edit_message(data, raw)
    secret = message[:secretEncryptedMessage]
    return if secret.blank? && !edit_envelope_flag?(info, raw)

    build_secret_edit_payload(secret, message, raw)
  end

  def secret_edit_message(data, raw)
    canonical_message(data).presence ||
      (raw[:Message] || raw[:message] || {}).with_indifferent_access
  end

  def build_secret_edit_payload(secret, message, raw)
    secret = (secret || {}).with_indifferent_access
    key = Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.normalize_key(
      secret[:targetMessageKey]
    )
    body = secret_edit_body(secret, message, raw)
    encrypted = secret.present? && body.blank?

    # Only claim the MESSAGE event when we can act (plaintext) or must skip (encrypted).
    return if key.blank? || key[:id].blank?
    return if body.blank? && !encrypted

    {
      key: key,
      edited_body: body,
      encrypted_edit: encrypted
    }
  end

  def secret_edit_body(secret, message, raw)
    extract_edited_body(secret).presence ||
      extract_edited_body(message).presence ||
      extract_edited_body(raw).presence
  end

  def canonical_message(data)
    raw = (data || {}).with_indifferent_access
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    message = (canonical[:message] || canonical['message'] || {}).with_indifferent_access
    return message if message.present?

    # canonicalize_data requires Info/key; edit envelopes still carry Message.
    (raw[:Message] || raw[:message] || {}).with_indifferent_access
  end

  def protocol_revoke?(protocol, raw)
    Custom::Whatsapp::EvolutionGo::MessageDeletePayloadExtractor.protocol_revoke_signal?(protocol, raw)
  end

  # Go 0.7+ may send IsEdit / messageType:"edit" alongside protocolMessage, or Info.Edit == "1".
  def protocol_edit_signal?(protocol, raw)
    edit_type?(protocol[:type]) ||
      edit_type?(protocol[:typeName]) ||
      edit_envelope_flag?(raw[:Info] || raw[:info] || {}, raw)
  end

  def edit_envelope_flag?(info, raw = {})
    info = (info || {}).with_indifferent_access
    raw = (raw || {}).with_indifferent_access
    return true if ActiveModel::Type::Boolean.new.cast(raw[:IsEdit])
    return true if raw[:messageType].to_s.downcase == 'edit'

    EDIT_INFO_VALUES.include?(info[:Edit].to_s)
  end

  def edit_type?(value)
    return false if value.nil?

    EDIT_TYPES.include?(value) || value.to_s.upcase.include?('EDIT')
  end

  def extract_edited_body(payload)
    payload = payload.with_indifferent_access
    edited = payload[:editedMessage] || payload[:message] || {}
    edited = edited.with_indifferent_access
    edited[:conversation] ||
      edited.dig(:extendedTextMessage, :text) ||
      edited.dig(:imageMessage, :caption) ||
      edited.dig(:videoMessage, :caption) ||
      edited.dig(:documentMessage, :caption)
  end
end
