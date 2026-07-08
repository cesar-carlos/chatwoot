# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::EvolutionGo::PayloadBuilders
  MESSAGE_TYPE_MAP = {
    'conversation' => 'text',
    'extendedTextMessage' => 'text',
    'imageMessage' => 'image',
    'documentMessage' => 'document',
    'audioMessage' => 'audio',
    'videoMessage' => 'video',
    'stickerMessage' => 'sticker',
    'locationMessage' => 'location',
    'liveLocationMessage' => 'location'
  }.freeze

  MEDIA_MESSAGE_KEYS = %w[
    imageMessage
    documentMessage
    audioMessage
    videoMessage
    stickerMessage
  ].freeze

  UNSUPPORTED_TYPE_PLACEHOLDERS = {
    'reactionMessage' => '[Reaction message]',
    'listMessage' => '[List message]',
    'listResponseMessage' => '[List message]'
  }.freeze

  private

  def map_message_type(message)
    return nil if message.blank?

    MEDIA_MESSAGE_KEYS.each do |key|
      return MESSAGE_TYPE_MAP[key] if message[key].present? || message[key.to_sym].present?
    end

    return 'location' if message['locationMessage'].present? || message[:locationMessage].present? ||
                        message['liveLocationMessage'].present? || message[:liveLocationMessage].present?

    body = extract_text_body(message)
    return 'text' if body.present?

    return 'text' if unsupported_placeholder(message).present?

    Rails.logger.info("[EVOLUTION_GO] unsupported inbound message keys=#{message.keys.join(',')}")
    nil
  end

  def build_message_hash(data, wa_id, message_type, key)
    return nil if wa_id.blank?

    if message_type.blank?
      message_type = 'text'
      data = data.merge(
        'message' => (data['message'] || data[:message] || {}).merge(
          'conversation' => '[Unsupported message type]'
        )
      )
    end
    remote_jid = group_remote_jid(key, wa_id)
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
    when 'location'
      apply_location_payload!(message_hash, data)
    else
      false
    end
  end

  def apply_text_payload!(message_hash, data)
    body = extract_text_body(data['message'] || data[:message] || {})
    return false if body.blank?

    body = Custom::Whatsapp::Evolution::MarkdownConverter.inbound(body) if convert_markdown_inbound?
    message_hash[:text] = { body: body }
    true
  end

  def extract_text_body(message)
    message = (message || {}).with_indifferent_access
    body = message['conversation'] ||
           message.dig('extendedTextMessage', 'text') ||
           message.dig('imageMessage', 'caption') ||
           message.dig('videoMessage', 'caption') ||
           message.dig('documentMessage', 'caption')
    return body if body.present?

    unsupported_placeholder(message)
  end

  def unsupported_placeholder(message)
    return nil if message.blank?

    message = message.with_indifferent_access
    type_key = UNSUPPORTED_TYPE_PLACEHOLDERS.keys.find { |key| message[key].present? }
    return UNSUPPORTED_TYPE_PLACEHOLDERS[type_key] if type_key

    return nil if message.key?('viewOnceMessageV2') || message.key?('ephemeralMessage')

    message.keys.any? { |key| key.to_s.end_with?('Message') } ? '[Unsupported message type]' : nil
  end

  def apply_location_payload!(message_hash, data)
    message = (data['message'] || data[:message] || {}).with_indifferent_access
    location = message['locationMessage'] || message['liveLocationMessage']
    return false if location.blank?

    location = location.with_indifferent_access
    latitude = location['degreesLatitude'] || location['latitude']
    longitude = location['degreesLongitude'] || location['longitude']
    return false if latitude.blank? || longitude.blank?

    name = location['name'].presence
    address = location['address'].presence
    maps_url = "https://maps.google.com/?q=#{latitude},#{longitude}"

    message_hash[:location] = {
      latitude: latitude,
      longitude: longitude,
      name: name,
      address: address,
      url: maps_url
    }.compact

    message_hash[:text] = { body: [name, address, maps_url].compact.join(' — ') } if name.present? || address.present?
    true
  end

  def convert_markdown_inbound?
    ActiveModel::Type::Boolean.new.cast(config['convert_markdown_inbound'])
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

  def group_remote_jid(key, wa_id)
    remote_jid = extract_remote_jid(key)
    return remote_jid if group_jid?(remote_jid)

    group_jid?(wa_id) ? wa_id : remote_jid
  end

  def group_jid?(remote_jid)
    Custom::Whatsapp::Evolution::GroupContactService.group_jid?(remote_jid)
  end
end
