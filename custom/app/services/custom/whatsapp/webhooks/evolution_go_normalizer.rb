# frozen_string_literal: true

class Custom::Whatsapp::Webhooks::EvolutionGoNormalizer
  include Custom::Whatsapp::Webhooks::EvolutionGo::PayloadBuilders
  include Custom::Whatsapp::Webhooks::EvolutionGo::StatusNormalizer

  attr_reader :channel, :envelope

  def initialize(channel, envelope)
    @channel = channel
    @envelope = envelope
  end

  def perform
    envelope_data = envelope.with_indifferent_access
    return unless envelope_data[:event] == 'MESSAGE'

    data = envelope_data[:data]
    return if data.blank?
    return if filtered?(data)

    normalize_message(data)
  end

  private

  def config
    channel.provider_config || Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS
  end

  def filtered?(data)
    key = data['key'] || data[:key] || {}
    remote_jid = extract_remote_jid(key)
    return true if from_me?(key) && ignore_from_me_echo?
    return true if ignore_groups? && group_jid?(remote_jid)
    return true if status_broadcast?(remote_jid)

    false
  end

  def normalize_message(data)
    key = data['key'] || data[:key] || {}
    wa_id = phone_from_jid(extract_remote_jid(key))
    message_type = map_message_type(data['message'] || data[:message] || {})
    message_hash = build_message_hash(data, wa_id, message_type, key)
    return if message_hash.blank?

    {
      contacts: [{ profile: { name: data['pushName'].to_s.presence || wa_id }, wa_id: wa_id }],
      messages: [message_hash]
    }
  end

  def extract_remote_jid(key)
    alt = key['remoteJidAlt'] || key[:remoteJidAlt]
    return alt if alt.present? && alt.to_s.end_with?('@s.whatsapp.net')

    key['remoteJid'] || key[:remoteJid]
  end

  def phone_from_jid(jid)
    digits = jid.to_s.split('@').first
    return if digits.blank?

    digits.gsub(/\D/, '')
  end

  def extract_text_body(message)
    return message['conversation'] if message['conversation'].present?
    return message.dig('extendedTextMessage', 'text') if message.dig('extendedTextMessage', 'text').present?

    nil
  end

  def from_me?(key)
    ActiveModel::Type::Boolean.new.cast(key['fromMe'] || key[:fromMe])
  end

  def ignore_from_me_echo?
    ActiveModel::Type::Boolean.new.cast(config['ignore_from_me_echo'])
  end

  def ignore_groups?
    ActiveModel::Type::Boolean.new.cast(config['ignore_groups'])
  end

  def group_jid?(remote_jid)
    remote_jid.to_s.end_with?('@g.us')
  end

  def status_broadcast?(remote_jid)
    remote_jid.to_s == 'status@broadcast'
  end
end
