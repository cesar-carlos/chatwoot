# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
module Custom::Whatsapp::Webhooks::Evolution::PayloadBuilders
  MESSAGE_TYPE_MAP = {
    'conversation' => 'text',
    'extendedTextMessage' => 'text',
    'imageMessage' => 'image',
    'documentMessage' => 'document',
    'audioMessage' => 'audio',
    'videoMessage' => 'video',
    'stickerMessage' => 'sticker',
    'locationMessage' => 'location',
    'liveLocationMessage' => 'location',
    'contactMessage' => 'contacts',
    'contactsArrayMessage' => 'contacts'
  }.freeze

  MEDIA_MESSAGE_KEYS = %w[
    imageMessage
    documentMessage
    audioMessage
    videoMessage
    stickerMessage
  ].freeze

  UNSUPPORTED_TYPE_PLACEHOLDERS = {
    'listMessage' => '[List message]'
  }.freeze

  CONTEXT_INFO_MESSAGE_KEYS = %w[
    extendedTextMessage
    imageMessage
    videoMessage
    audioMessage
    documentMessage
    stickerMessage
    contactMessage
    locationMessage
    buttonsResponseMessage
    templateButtonReplyMessage
    listResponseMessage
  ].freeze

  private

  def build_message_hash(data, wa_id, message_type, key)
    return nil if wa_id.blank?
    # Reactions are handled by MessageReactionSyncService — never create a text placeholder.
    return nil if data.dig('message', 'reactionMessage').present? || data.dig(:message, :reactionMessage).present?

    message_type = 'text' if message_type.blank?
    message_hash = {
      from: wa_id,
      id: key['id'],
      timestamp: data['messageTimestamp'].to_s,
      type: message_type,
      evolution_remote_jid: key['remoteJid']
    }.compact

    case message_type
    when 'text'
      return nil unless apply_text_payload!(message_hash, data)
    when 'image', 'video', 'audio', 'document', 'sticker'
      message_hash[message_type.to_sym] = build_media_payload(data, message_type)
    when 'location'
      return nil unless apply_location_payload!(message_hash, data)
    when 'contacts'
      return nil unless apply_contacts_payload!(message_hash, data)
    end

    message_hash
  end

  def map_message_type(data)
    mapped = MESSAGE_TYPE_MAP[data['messageType'].to_s]
    return mapped if mapped.present?

    inferred = infer_type_from_message(data['message'])
    return inferred if inferred.present?

    unsupported_message_type?(data['message']) ? 'text' : nil
  end

  def infer_type_from_message(message)
    return nil if message.blank?

    MEDIA_MESSAGE_KEYS.each do |key|
      return MESSAGE_TYPE_MAP[key] if message[key].present?
    end

    return 'location' if message['locationMessage'].present? || message['liveLocationMessage'].present?
    return 'contacts' if message['contactMessage'].present? || message['contactsArrayMessage'].present?
    return 'text' if message['conversation'].present? || message['extendedTextMessage'].present?
    return 'text' if interactive_reply_body(message).present?

    nil
  end

  def build_media_payload(data, type)
    message_key = media_message_key(data['message'], type)
    media = data.dig('message', message_key) || {}

    {
      id: data.dig('key', 'id'),
      caption: media['caption'],
      filename: media['fileName'],
      mimetype: media['mimetype'],
      _evolution_message: {
        'key' => data['key'],
        'message' => data['message'],
        'messageTimestamp' => data['messageTimestamp']
      }
    }.compact
  end

  def media_message_key(message, type)
    return 'stickerMessage' if type == 'sticker' && message&.dig('stickerMessage').present?

    "#{type}Message"
  end

  def apply_location_payload!(message_hash, data)
    message = data['message'] || {}
    location = message['locationMessage'] || message['liveLocationMessage']
    return false if location.blank?

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

  def apply_contacts_payload!(message_hash, data)
    message = data['message'] || {}
    contacts = extract_contacts(message)
    return false if contacts.blank?

    message_hash[:contacts] = contacts
    true
  end

  def extract_contacts(message)
    if message['contactsArrayMessage'].present?
      Array.wrap(message.dig('contactsArrayMessage', 'contacts')).filter_map do |entry|
        build_contact_hash(entry['contactMessage'] || entry)
      end
    elsif message['contactMessage'].present?
      [build_contact_hash(message['contactMessage'])].compact
    else
      []
    end
  end

  def build_contact_hash(contact)
    return nil if contact.blank?

    display_name = contact['displayName'].presence
    vcard = contact['vcard'].to_s
    phone = vcard[/waid=\d+:(\+?[\d\s()-]+)/, 1] || vcard[/TEL[^:]*:([^\n]+)/, 1]
    phone_list = if phone.present?
                   [{ phone: phone.gsub(/\D/, '').presence || phone.strip }]
                 else
                   [{ phone: 'Phone number is not available' }]
                 end

    {
      name: {
        formatted_name: display_name,
        first_name: display_name
      }.compact,
      phones: phone_list
    }
  end

  def add_reply_context!(message_hash, data)
    context_info = extract_context_info(data)
    return if context_info.blank? || context_info['stanzaId'].blank?

    message_hash[:context] = { id: context_info['stanzaId'] }
  end

  def extract_context_info(data)
    message = data['message'] || {}
    CONTEXT_INFO_MESSAGE_KEYS.each do |type|
      context_info = message.dig(type, 'contextInfo')
      return context_info if context_info.present?
    end

    nil
  end

  def apply_text_payload!(message_hash, data)
    body = extract_text_body(data)
    return false if body.blank?
    return false if ignore_survey_link?(body)

    body = format_group_message_body(body, data)
    body = Custom::Whatsapp::Evolution::MarkdownConverter.inbound(body) if convert_markdown_inbound?
    message_hash[:text] = { body: body }
    true
  end

  def extract_text_body(data)
    message = data['message'] || {}
    body = message['conversation'] ||
           message.dig('extendedTextMessage', 'text') ||
           message.dig('imageMessage', 'caption') ||
           message.dig('videoMessage', 'caption') ||
           message.dig('documentMessage', 'caption') ||
           interactive_reply_body(message)
    return body if body.present?

    unsupported_placeholder(data['message'])
  end

  def interactive_reply_body(message)
    message = (message || {}).with_indifferent_access

    button_reply_body(message['buttonsResponseMessage']) ||
      template_reply_body(message['templateButtonReplyMessage']) ||
      list_reply_body(message['listResponseMessage'])
  end

  def button_reply_body(button)
    return if button.blank?

    button = button.with_indifferent_access
    button['selectedDisplayText'].presence || button['selectedButtonId'].presence
  end

  def template_reply_body(template)
    return if template.blank?

    template = template.with_indifferent_access
    template['selectedDisplayText'].presence || template['selectedId'].presence
  end

  def list_reply_body(list)
    return if list.blank?

    list = list.with_indifferent_access
    list.dig('singleSelectReply', 'selectedRowId').presence ||
      list['title'].presence ||
      list['description'].presence
  end

  def unsupported_message_type?(message)
    unsupported_placeholder(message).present?
  end

  def unsupported_placeholder(message)
    return nil if message.blank?

    type_key = UNSUPPORTED_TYPE_PLACEHOLDERS.keys.find { |key| message[key].present? }
    return UNSUPPORTED_TYPE_PLACEHOLDERS[type_key] if type_key

    return nil if message.key?('viewOnceMessageV2') || message.key?('ephemeralMessage')

    message.keys.any? { |key| key.end_with?('Message') } ? '[Unsupported message type]' : nil
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
