# frozen_string_literal: true

class Custom::Whatsapp::Providers::EvolutionService < Whatsapp::Providers::BaseService
  include Custom::Whatsapp::Providers::EvolutionServiceOutbound

  def send_message(phone_number, message)
    @message = message

    if contact_attachment?(message)
      send_contact_card_message(phone_number, message) # FORK: share contact card
    elsif message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif input_select_items(message).present?
      send_input_select_message(phone_number, message)
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
    return false if config['base_url'].blank? || config['instance_name'].blank? || config['api_key'].blank?

    cached = Rails.cache.read(connection_validation_cache_key)
    return cached unless cached.nil?

    open = connection_open?(api_client.connection_state)
    Rails.cache.write(connection_validation_cache_key, open, expires_in: connection_validation_cache_ttl)
    open
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.warn("[EVOLUTION] validate_provider_config failed channel=#{whatsapp_channel.id}: #{e.message}")
    false
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
    Rails.logger.warn("[EVOLUTION] validate_provider_config network error channel=#{whatsapp_channel.id}: #{e.message}")
    false
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

  def handle_error(response, message)
    super
    create_send_error_private_note!(message, response)
  end

  private

  def send_text_message(phone_number, message)
    response = api_client.send_text(
      number: phone_number,
      text: apply_outbound_text(message.outgoing_content, message),
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay
    )
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def send_input_select_message(phone_number, message)
    items = input_select_items(message)
    quoted = build_quoted_context(phone_number, message)
    delay = outbound_delay
    title = apply_outbound_text(message.outgoing_content.presence || 'Please choose an option', message)

    response = dispatch_input_select(phone_number, title, items, quoted, delay)
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def send_attachment_message(phone_number, message)
    message_id = deliver_attachment_batch(phone_number, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def deliver_attachment_batch(phone_number, message)
    message_id = nil

    message.attachments.each_with_index do |attachment, index|
      response = dispatch_attachment(
        phone_number: phone_number,
        attachment: attachment,
        media_source: Custom::Whatsapp::Evolution::MediaPayload.for_attachment(attachment),
        message: message,
        include_caption: index.zero?
      )
      message_id = process_attachment_response(response, message, index, message_id)
      return message_id if message_id == :failed
    end

    message_id == :failed ? nil : message_id
  end

  def process_attachment_response(response, message, index, message_id)
    if index.zero?
      first_id = process_response(response, message)
      return :failed if first_id.blank?

      return first_id
    end

    return message_id if response.success?

    Rails.logger.warn(
      "[EVOLUTION] secondary attachment send failed for message #{message.id}: HTTP #{response.code}"
    )
    notify_partial_attachment_failure!(message, index + 1)
    message_id
  end

  def notify_partial_attachment_failure!(message, attachment_index)
    return unless notify_send_errors_private?
    return if message.blank? || message.conversation.blank?

    message.conversation.messages.create!(
      account_id: message.account_id,
      inbox_id: message.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: message.sender,
      content: "Attachment ##{attachment_index} could not be sent to WhatsApp."
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] failed to create partial attachment private note: #{e.message}"
  end

  def dispatch_attachment(phone_number:, attachment:, media_source:, message:, include_caption: true)
    quoted = build_quoted_context(phone_number, message)
    delay = outbound_delay
    mediatype = attachment_mediatype(attachment)
    return send_audio_attachment(phone_number, media_source, quoted, delay) if mediatype == 'audio'

    api_client.send_media(
      number: phone_number,
      mediatype: mediatype,
      media: media_source,
      caption: include_caption ? attachment_caption(message, mediatype) : nil,
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
    return 'sticker' if attachment.file_type == 'sticker'
    return attachment.file_type if %w[image audio video].include?(attachment.file_type)

    'document'
  end

  def normalize_phone(phone)
    phone.to_s.gsub(/\D/, '')
  end

  def connection_open?(response)
    return false unless response.success?

    state = response.parsed_response.dig('instance', 'state') || response.parsed_response['state']
    state.to_s == 'open'
  end

  def connection_validation_cache_key
    "evolution:connection_validation:#{whatsapp_channel.id}"
  end

  def connection_validation_cache_ttl
    Custom::Whatsapp::Evolution::ConnectionService::CONNECTION_STATE_CACHE_TTL
  end
end
