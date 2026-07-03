# frozen_string_literal: true

module Custom::Whatsapp::Webhooks::Evolution::MessageFilters
  private

  def ignore_message?(data)
    key = data['key'] || {}
    remote_jid = key['remoteJid'].to_s

    ignored_from_me_echo?(key) ||
      Custom::Whatsapp::Evolution::RemoteJidFilter.skip_remote_jid?(remote_jid, config)
  end

  def ignored_from_me_echo?(key)
    return false if import_mode

    ActiveModel::Type::Boolean.new.cast(config['ignore_from_me_echo']) && key['fromMe']
  end

  def ignore_survey_link?(body)
    ActiveModel::Type::Boolean.new.cast(config['ignore_survey_links']) &&
      body.include?('/survey/responses/') &&
      body.include?('http')
  end

  def unwrap_ephemeral_message(data)
    message = data['message']
    return data unless message.is_a?(Hash)

    inner = message['ephemeralMessage']&.dig('message') ||
            message['viewOnceMessageV2']&.dig('message')
    return data if inner.blank?

    data.merge('message' => inner)
  end

  def group_jid?(jid)
    jid.to_s.end_with?('@g.us')
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
end
