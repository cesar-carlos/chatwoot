# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionNormalizer
  pattr_initialize [:channel!, :envelope!]

  MESSAGE_TYPE_MAP = {
    'conversation' => 'text',
    'extendedTextMessage' => 'text',
    'imageMessage' => 'image',
    'documentMessage' => 'document',
    'audioMessage' => 'audio',
    'videoMessage' => 'video'
  }.freeze

  MEDIA_MESSAGE_KEYS = %w[
    imageMessage
    documentMessage
    audioMessage
    videoMessage
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
    channel.provider_config || Custom::Whatsapp::Evolution::ProviderConfig::DEFAULTS
  end

  def normalize_message(data)
    return nil if ignore_message?(data)

    wa_id = resolve_wa_id(data['key'] || data[:key])
    message_type = map_message_type(data)
    message_hash = build_message_hash(data, wa_id, message_type)
    return nil if message_hash.blank?

    add_reply_context!(message_hash, data)

    {
      contacts: [{ profile: { name: data['pushName'].to_s }, wa_id: wa_id }],
      messages: [message_hash]
    }
  end

  def build_message_hash(data, wa_id, message_type)
    return nil if wa_id.blank? || message_type.blank?

    message_hash = {
      from: wa_id,
      id: data.dig('key', 'id'),
      timestamp: data['messageTimestamp'].to_s,
      type: message_type
    }

    case message_type
    when 'text'
      return nil unless apply_text_payload!(message_hash, data)

    when 'image', 'video', 'audio', 'document'
      message_hash[message_type.to_sym] = build_media_payload(data, message_type)
    end

    message_hash
  end

  def normalize_status(data)
    key = data['key'] || {}
    update = data['update'] || {}
    status_code = update['status']
    return nil if key['id'].blank? || status_code.nil?

    {
      statuses: [
        {
          id: key['id'],
          status: map_status(status_code),
          timestamp: Time.current.to_i.to_s,
          recipient_id: jid_to_phone(key['remoteJid'])
        }
      ]
    }
  end

  def map_message_type(data)
    mapped = MESSAGE_TYPE_MAP[data['messageType'].to_s]
    return mapped if mapped.present?

    infer_type_from_message(data['message'])
  end

  def infer_type_from_message(message)
    return nil if message.blank?

    MEDIA_MESSAGE_KEYS.each do |key|
      return MESSAGE_TYPE_MAP[key] if message[key].present?
    end

    return 'text' if message['conversation'].present? || message['extendedTextMessage'].present?

    nil
  end

  def build_media_payload(data, type)
    message_key = "#{type}Message"
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

  def add_reply_context!(message_hash, data)
    context_info = extract_context_info(data)
    return if context_info.blank? || context_info['stanzaId'].blank?

    message_hash[:context] = { id: context_info['stanzaId'] }
  end

  def extract_context_info(data)
    message = data['message'] || {}
    %w[extendedTextMessage imageMessage videoMessage audioMessage documentMessage].each do |type|
      context_info = message.dig(type, 'contextInfo')
      return context_info if context_info.present?
    end

    nil
  end

  def apply_text_payload!(message_hash, data)
    body = extract_text_body(data)
    return false if body.blank?

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

  def extract_text_body(data)
    message = data['message'] || {}
    message['conversation'] ||
      message.dig('extendedTextMessage', 'text') ||
      message.dig('imageMessage', 'caption') ||
      message.dig('videoMessage', 'caption') ||
      message.dig('documentMessage', 'caption')
  end

  def resolve_wa_id(key)
    key ||= {}
    jid = if key['addressingMode'] == 'lid' && key['remoteJidAlt'].present?
            key['remoteJidAlt']
          else
            key['remoteJid']
          end
    jid_to_phone(jid)
  end

  def jid_to_phone(jid)
    phone = jid.to_s.split('@').first.presence
    return phone unless merge_brazil_contacts? && phone&.start_with?('55')

    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(phone)
  end

  def merge_brazil_contacts?
    ActiveModel::Type::Boolean.new.cast(config['merge_brazil_contacts'])
  end

  def map_status(code)
    case code.to_i
    when 3, 4 then 'read'
    when 2 then 'delivered'
    else 'sent'
    end
  end
end
