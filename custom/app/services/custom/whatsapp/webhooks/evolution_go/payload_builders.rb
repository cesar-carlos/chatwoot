# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
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
    'reactionMessage' => '[Reaction message]',
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

  def map_message_type(message)
    return nil if message.blank?

    message = message.with_indifferent_access

    MEDIA_MESSAGE_KEYS.each do |key|
      return MESSAGE_TYPE_MAP[key] if message[key].present?
    end

    return 'location' if message['locationMessage'].present? || message['liveLocationMessage'].present?
    return 'contacts' if message['contactMessage'].present? || message['contactsArrayMessage'].present?
    return 'text' if interactive_reply_body(message).present?

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
    when 'contacts'
      apply_contacts_payload!(message_hash, data)
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
           message.dig('documentMessage', 'caption') ||
           interactive_reply_body(message)
    return body if body.present?

    unsupported_placeholder(message)
  end

  def interactive_reply_body(message)
    message = (message || {}).with_indifferent_access

    button = message['buttonsResponseMessage']
    if button.present?
      button = button.with_indifferent_access
      return button['selectedDisplayText'].presence || button['selectedButtonId'].presence
    end

    template = message['templateButtonReplyMessage']
    if template.present?
      template = template.with_indifferent_access
      return template['selectedDisplayText'].presence || template['selectedId'].presence
    end

    list = message['listResponseMessage']
    return if list.blank?

    list = list.with_indifferent_access
    list.dig('singleSelectReply', 'selectedRowId').presence ||
      list['title'].presence ||
      list['description'].presence
  end

  def add_reply_context!(message_hash, data)
    context_info = extract_context_info(data)
    return if context_info.blank?

    stanza_id = context_info['stanzaId'] || context_info[:stanzaId]
    return if stanza_id.blank?

    message_hash[:context] = { id: stanza_id }
  end

  def extract_context_info(data)
    message = (data['message'] || data[:message] || {}).with_indifferent_access
    CONTEXT_INFO_MESSAGE_KEYS.each do |type|
      context_info = message.dig(type, 'contextInfo')
      return context_info.with_indifferent_access if context_info.present?
    end

    top_level = data['contextInfo'] || data[:contextInfo]
    top_level.present? ? top_level.with_indifferent_access : nil
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

  def apply_contacts_payload!(message_hash, data)
    message = (data['message'] || data[:message] || {}).with_indifferent_access
    contacts = extract_contacts(message)
    return false if contacts.blank?

    message_hash[:contacts] = contacts
    true
  end

  def extract_contacts(message)
    if message['contactsArrayMessage'].present?
      Array.wrap(message.dig('contactsArrayMessage', 'contacts')).filter_map do |entry|
        entry = (entry || {}).with_indifferent_access
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

    contact = contact.with_indifferent_access
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
# rubocop:enable Metrics/ModuleLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
