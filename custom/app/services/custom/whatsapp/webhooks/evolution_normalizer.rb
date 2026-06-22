# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- maps Evolution message types to Chatwoot webhook shape
class Custom::Whatsapp::Webhooks::EvolutionNormalizer
  attr_reader :channel, :envelope, :import_mode

  def initialize(channel:, envelope:, import_mode: false)
    @channel = channel
    @envelope = envelope
    @import_mode = import_mode
  end

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

    {
      contacts: [{ profile: { name: data['pushName'].to_s }, wa_id: wa_id }],
      messages: [message_hash]
    }
  end

  # rubocop:disable Metrics/CyclomaticComplexity -- one branch per Evolution message type
  # rubocop:disable Metrics/MethodLength -- one branch per Evolution message type
  def build_message_hash(data, wa_id, message_type, key)
    return nil if wa_id.blank?

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
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

  def normalize_status(data)
    data = data.with_indifferent_access
    return normalize_evolution_status_payload(data) if evolution_status_payload?(data)

    normalize_baileys_status_payload(data)
  end

  def evolution_status_payload?(data)
    data[:keyId].present?
  end

  def normalize_evolution_status_payload(data)
    status_value = data[:status]
    return nil if data[:keyId].blank? || status_value.blank?

    build_status_hash(
      id: data[:keyId],
      status: map_status(status_value),
      remote_jid: data[:remoteJid],
      timestamp: status_timestamp(data),
      key: nil
    )
  end

  def normalize_baileys_status_payload(data)
    key = data[:key] || {}
    update = data[:update] || {}
    status_code = update[:status]
    message_id = key[:id]
    return nil if message_id.blank? || status_code.nil?

    build_status_hash(
      id: message_id,
      status: map_status(status_code),
      remote_jid: key[:remoteJid],
      timestamp: status_timestamp(data),
      key: key
    )
  end

  def build_status_hash(id:, status:, remote_jid:, timestamp:, key: nil)
    {
      statuses: [
        {
          id: id,
          status: status,
          timestamp: timestamp.to_s,
          recipient_id: jid_resolver.recipient_id_for_status(remote_jid, key)
        }
      ]
    }
  end

  def status_timestamp(data)
    data['messageTimestamp'].presence || data['timestamp'].presence || Time.current.to_i
  end

  def map_message_type(data)
    mapped = MESSAGE_TYPE_MAP[data['messageType'].to_s]
    return mapped if mapped.present?

    inferred = infer_type_from_message(data['message'])
    return inferred if inferred.present?

    unsupported_message_type?(data['message']) ? 'text' : nil
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- type inference from Baileys payload keys
  def infer_type_from_message(message)
    return nil if message.blank?

    MEDIA_MESSAGE_KEYS.each do |key|
      return MESSAGE_TYPE_MAP[key] if message[key].present?
    end

    return 'location' if message['locationMessage'].present? || message['liveLocationMessage'].present?
    return 'contacts' if message['contactMessage'].present? || message['contactsArrayMessage'].present?
    return 'text' if message['conversation'].present? || message['extendedTextMessage'].present?

    nil
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- location vs live location fields
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
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

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
    %w[extendedTextMessage imageMessage videoMessage audioMessage documentMessage stickerMessage].each do |type|
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

  def ignore_message?(data)
    key = data['key'] || {}
    remote_jid = key['remoteJid'].to_s

    ignored_from_me_echo?(key) ||
      ignored_status_broadcast?(remote_jid) ||
      ignored_group_message?(remote_jid) ||
      ignore_jid?(remote_jid)
  end

  def ignored_from_me_echo?(key)
    return false if import_mode

    ActiveModel::Type::Boolean.new.cast(config['ignore_from_me_echo']) && key['fromMe']
  end

  def ignored_status_broadcast?(remote_jid)
    remote_jid == 'status@broadcast' && config['ignore_status_broadcast'] != false
  end

  def ignored_group_message?(remote_jid)
    remote_jid.end_with?('@g.us') && config['groups_ignore'] != false
  end

  def ignore_jid?(remote_jid)
    Array(config['ignore_jids']).any? { |pattern| remote_jid.include?(pattern.to_s) }
  end

  def ignore_survey_link?(body)
    ActiveModel::Type::Boolean.new.cast(config['ignore_survey_links']) &&
      body.include?('/survey/responses/') &&
      body.include?('http')
  end

  def extract_text_body(data)
    message = data['message'] || {}
    body = message['conversation'] ||
           message.dig('extendedTextMessage', 'text') ||
           message.dig('imageMessage', 'caption') ||
           message.dig('videoMessage', 'caption') ||
           message.dig('documentMessage', 'caption')
    return body if body.present?

    unsupported_placeholder(data['message'])
  end

  def unsupported_message_type?(message)
    unsupported_placeholder(message).present?
  end

  UNSUPPORTED_TYPE_PLACEHOLDERS = {
    'reactionMessage' => '[Reaction message]',
    'listMessage' => '[List message]',
    'listResponseMessage' => '[List message]'
  }.freeze

  # rubocop:disable Metrics/CyclomaticComplexity -- explicit branches per Baileys wrapper key
  def unsupported_placeholder(message)
    return nil if message.blank?

    type_key = UNSUPPORTED_TYPE_PLACEHOLDERS.keys.find { |key| message[key].present? }
    return UNSUPPORTED_TYPE_PLACEHOLDERS[type_key] if type_key

    return nil if message.key?('viewOnceMessageV2') || message.key?('ephemeralMessage')

    message.keys.any? { |key| key.end_with?('Message') } ? '[Unsupported message type]' : nil
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def unwrap_ephemeral_message(data)
    message = data['message']
    return data unless message.is_a?(Hash)

    inner = message['ephemeralMessage']&.dig('message') ||
            message['viewOnceMessageV2']&.dig('message')
    return data if inner.blank?

    data.merge('message' => inner)
  end

  def resolve_wa_id(key)
    key ||= {}
    remote_jid = key['remoteJid'].to_s
    return group_wa_id(remote_jid) if group_jid?(remote_jid)

    jid_resolver.phone_from_message_key(key)
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::Evolution::JidResolver.new(config)
  end

  def group_jid?(jid)
    jid.to_s.end_with?('@g.us')
  end

  def group_wa_id(remote_jid)
    remote_jid.to_s.split('@').first
  end

  def format_group_message_body(body, data)
    return body unless format_group_messages?

    key = data['key'] || {}
    return body unless group_jid?(key['remoteJid'])

    participant_jid = key['participant'].to_s
    label = data['pushName'].to_s.strip.presence || jid_to_phone(participant_jid)
    return body if label.blank?

    "**#{label}:**\n\n#{body}"
  end

  def format_group_messages?
    ActiveModel::Type::Boolean.new.cast(config['format_group_messages'])
  end

  def jid_to_phone(jid)
    phone = jid.to_s.split('@').first.presence
    return phone unless merge_brazil_contacts? && phone&.start_with?('55')

    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(phone)
  end

  def merge_brazil_contacts?
    ActiveModel::Type::Boolean.new.cast(config['merge_brazil_contacts'])
  end

  def convert_markdown_inbound?
    ActiveModel::Type::Boolean.new.cast(config['convert_markdown_inbound'])
  end

  def map_status(code)
    return map_status_string(code) if code.is_a?(String) && code.match?(/[A-Za-z]/)

    case code.to_i
    when 3 then 'delivered'
    when 4, 5 then 'read'
    when 0 then 'failed'
    else 'sent'
    end
  end

  def map_status_string(status)
    case status.to_s.upcase
    when 'DELIVERY_ACK' then 'delivered'
    when 'READ', 'PLAYED' then 'read'
    when 'ERROR' then 'failed'
    else 'sent'
    end
  end
end
# rubocop:enable Metrics/ClassLength
