# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::MessageEditPayloadExtractor
  EDIT_EVENTS = %w[MESSAGES_EDITED MESSAGE_EDIT SEND_MESSAGE_UPDATE].freeze
  EDIT_TYPES = [
    14, '14',
    'EDIT', 'edit',
    'MESSAGE_EDIT', 'message_edit',
    'PROTOCOL_MESSAGE_TYPE_MESSAGE_EDIT'
  ].freeze

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
    message = canonical_message(data)
    protocol = message[:protocolMessage]
    return if protocol.blank?

    protocol = protocol.with_indifferent_access
    return unless edit_type?(protocol[:type])

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
    return if secret.blank? && !info_edit_flag?(info, raw)

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

    {
      key: key || {},
      edited_body: body,
      encrypted_edit: secret.present? && body.blank?
    }
  end

  def secret_edit_body(secret, message, raw)
    extract_edited_body(secret).presence ||
      extract_edited_body(message).presence ||
      extract_edited_body(raw).presence
  end

  def canonical_message(data)
    canonical = Custom::Whatsapp::Webhooks::EvolutionGoPayloadAdapter.canonicalize_data(data)
    (canonical[:message] || canonical['message'] || {}).with_indifferent_access
  end

  def info_edit_flag?(info, raw = {})
    return true if ActiveModel::Type::Boolean.new.cast(raw[:IsEdit])

    edit = info[:Edit].to_s
    edit.present? && edit != '0' && %w[false False FALSE].exclude?(edit)
  end

  def edit_type?(value)
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
