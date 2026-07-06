# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::PayloadBuilders
  MESSAGE_TYPE_MAP = {
    'conversation' => 'text',
    'extendedTextMessage' => 'text',
    'imageMessage' => 'image',
    'documentMessage' => 'document',
    'audioMessage' => 'audio',
    'videoMessage' => 'video',
    'stickerMessage' => 'sticker'
  }.freeze

  MEDIA_MESSAGE_KEYS = %w[
    imageMessage
    documentMessage
    audioMessage
    videoMessage
    stickerMessage
  ].freeze

  private

  def map_message_type(message)
    return nil if message.blank?

    MEDIA_MESSAGE_KEYS.each do |key|
      return MESSAGE_TYPE_MAP[key] if message[key].present? || message[key.to_sym].present?
    end

    return 'text' if extract_text_body(message).present?

    nil
  end

  def build_message_hash(data, wa_id, message_type, key)
    return nil if wa_id.blank?

    message_type = 'text' if message_type.blank?
    remote_jid = extract_remote_jid(key)
    message_hash = {
      from: wa_id,
      id: key['id'] || key[:id],
      timestamp: (data['messageTimestamp'] || data[:messageTimestamp]).to_s,
      type: message_type,
      evolution_go_remote_jid: remote_jid
    }.compact

    return nil unless apply_message_type_payload!(message_hash, data, message_type)

    message_hash
  end

  def apply_message_type_payload!(message_hash, data, message_type)
    case message_type
    when 'text'
      apply_text_payload!(message_hash, data)
    when 'image', 'video', 'audio', 'document', 'sticker'
      message_hash[message_type.to_sym] = build_media_payload(data, message_type)
      true
    else
      false
    end
  end

  def apply_text_payload!(message_hash, data)
    body = extract_text_body(data['message'] || data[:message] || {})
    return false if body.blank?

    message_hash[:text] = { body: body }
    true
  end

  def build_media_payload(data, type)
    message = data['message'] || data[:message] || {}
    message_key = media_message_key(message, type)
    media = message[message_key] || message[message_key.to_sym] || {}

    media_fields(media).merge(
      id: (data.dig('key', 'id') || data.dig(:key, :id)),
      _evolution_go_message: evolution_go_message_metadata(data, message)
    ).compact
  end

  def media_fields(media)
    {
      caption: media['caption'] || media[:caption],
      filename: media['fileName'] || media[:fileName],
      mimetype: media['mimetype'] || media[:mimetype]
    }
  end

  def evolution_go_message_metadata(data, message)
    {
      'key' => data['key'] || data[:key],
      'message' => message,
      'messageTimestamp' => data['messageTimestamp'] || data[:messageTimestamp]
    }
  end

  def media_message_key(message, type)
    return 'stickerMessage' if type == 'sticker' && (message['stickerMessage'].present? || message[:stickerMessage].present?)

    "#{type}Message"
  end
end
