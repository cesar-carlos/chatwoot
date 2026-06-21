# frozen_string_literal: true

class Custom::Whatsapp::Providers::EvolutionService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, _template_info, message)
    return send_message(phone_number, message) if send_templates_as_text?

    @message = message
    message.external_error = 'Templates are not supported for the Evolution provider'
    message.status = :failed
    message.save!
    nil
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
    true
  end

  def validate_provider_config?
    config = whatsapp_channel.provider_config || {}
    return false if config['base_url'].blank? || config['instance_name'].blank?
    return true if config['api_key'].blank?

    response = api_client.connection_state
    response.success?
  rescue StandardError
    config['api_key'].present?
  end

  def media_url(_media_id)
    nil
  end

  def api_headers
    { 'apikey' => whatsapp_channel.provider_config['api_key'] }
  end

  def error_message(response)
    body = response.parsed_response
    return body.to_s unless body.is_a?(Hash)

    body.dig('response', 'message') || body['message'] || body.dig('error', 'message') || body['error']
  end

  def process_response(response, message)
    parsed = response.parsed_response
    if response.success? && parsed.is_a?(Hash) && parsed.dig('key', 'id').present?
      parsed.dig('key', 'id')
    else
      handle_error(response, message)
      nil
    end
  end

  private

  def send_text_message(phone_number, message)
    response = api_client.send_text(
      number: phone_number,
      text: apply_outbound_text(message.outgoing_content, message),
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay
    )
    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    media_source = Custom::Whatsapp::Evolution::MediaPayload.for_attachment(attachment)
    response = dispatch_attachment(
      phone_number: phone_number,
      attachment: attachment,
      media_source: media_source,
      message: message
    )

    process_response(response, message)
  end

  def dispatch_attachment(phone_number:, attachment:, media_source:, message:)
    quoted = build_quoted_context(phone_number, message)
    delay = outbound_delay
    mediatype = attachment_mediatype(attachment)
    return send_audio_attachment(phone_number, media_source, quoted, delay) if mediatype == 'audio'

    api_client.send_media(
      number: phone_number,
      mediatype: mediatype,
      media: media_source,
      caption: attachment_caption(message, mediatype),
      file_name: attachment.file.filename.to_s,
      quoted: quoted,
      delay: delay
    )
  end

  def send_audio_attachment(phone_number, media_source, quoted, delay)
    api_client.send_audio(
      number: phone_number,
      audio: media_source,
      quoted: quoted,
      delay: delay
    )
  end

  def attachment_caption(message, mediatype)
    caption = message.content.presence
    return caption unless caption.present? && mediatype != 'audio'

    apply_outbound_text(caption, message)
  end

  def attachment_mediatype(attachment)
    return attachment.file_type if %w[image audio video].include?(attachment.file_type)

    'document'
  end

  def apply_outbound_text(body, message)
    return body unless sign_msg?

    sender_name = message.sender&.available_name
    return body if sender_name.blank?

    delimiter = provider_config['sign_delimiter'].to_s.gsub('\\n', "\n").presence || "\n"
    ["*#{sender_name}:*", body].join(delimiter)
  end

  def build_quoted_context(phone_number, message)
    reply_id = message.content_attributes[:in_reply_to_external_id]
    return nil if reply_id.blank?

    {
      key: {
        id: reply_id,
        remoteJid: "#{normalize_phone(phone_number)}@s.whatsapp.net",
        fromMe: false
      },
      message: { conversation: reply_snippet(message, reply_id) }
    }
  end

  def reply_snippet(message, reply_id)
    original = message.conversation.messages.find_by(source_id: reply_id)
    original&.content&.truncate(100).to_s
  end

  def outbound_delay
    return nil unless send_random_delay?

    rand(500..2000)
  end

  def sign_msg?
    ActiveModel::Type::Boolean.new.cast(provider_config['sign_msg'])
  end

  def send_random_delay?
    ActiveModel::Type::Boolean.new.cast(provider_config['send_random_delay'])
  end

  def send_templates_as_text?
    ActiveModel::Type::Boolean.new.cast(provider_config['send_templates_as_text'])
  end

  def provider_config
    whatsapp_channel.provider_config || {}
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.new(
      base_url: provider_config['base_url'],
      api_key: provider_config['api_key'],
      instance_name: provider_config['instance_name']
    )
  end
end
