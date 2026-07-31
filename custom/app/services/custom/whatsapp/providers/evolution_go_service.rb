# frozen_string_literal: true

class Custom::Whatsapp::Providers::EvolutionGoService < Whatsapp::Providers::BaseService
  include Custom::Whatsapp::Providers::EvolutionGoServiceOutbound

  def send_message(phone_number, message)
    @message = message
    destination = outbound_destination(phone_number, message)
    if contact_attachment?(message)
      send_contact_card_message(destination, message)
    elsif location_attachment?(message)
      send_location_message(destination, message)
    elsif message.attachments.present?
      send_attachment_message(destination, message)
    elsif input_select_items(message).present?
      send_input_select_message(destination, message)
    else
      send_text_message(destination, message)
    end
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    fail_message_with_network_error!(message, e)
    nil
  end

  def send_template(phone_number, _template_info, message)
    return send_message(phone_number, message) if send_templates_as_text?

    @message = message
    message.external_error = 'Templates are not supported for the Evolution Go provider'
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
    return false if config['base_url'].blank? || config['instance_token'].blank?

    cached = Rails.cache.read(connection_validation_cache_key)
    return cached unless cached.nil?

    open = connection_open?
    Rails.cache.write(connection_validation_cache_key, open, expires_in: 60.seconds)
    open
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn("[EVOLUTION_GO] validate_provider_config failed channel=#{whatsapp_channel.id}: #{e.message}")
    false
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
    Rails.logger.warn("[EVOLUTION_GO] validate_provider_config network error channel=#{whatsapp_channel.id}: #{e.message}")
    false
  end

  def media_url(_media_id)
    nil
  end

  def api_headers
    { 'apikey' => whatsapp_channel.provider_config['instance_token'] }
  end

  def error_message(response)
    return 'Unknown Evolution Go error' if response.nil?

    body = response.parsed_response
    return body.to_s unless body.is_a?(Hash)

    error = body['error']
    text = body['message'] || (error.is_a?(Hash) ? error['message'] : error)
    return Custom::Whatsapp::EvolutionGo::ApiError.friendly_session_message if session_disconnected?(text)

    text
  end

  def process_response(response, message)
    parsed = response.parsed_response
    source_id = extract_source_id(parsed)
    if response.success? && source_id.present?
      source_id
    else
      handle_error(response, message)
      create_send_error_private_note!(message, response)
      nil
    end
  end

  def handle_error(response, message)
    super
    return if message.blank?

    error_text = error_message(response).presence || "Unknown Evolution Go error (HTTP #{response&.code})"
    return if message.external_error.present?

    message.external_error = error_text
    message.status = :failed
    message.save!
  end

  private

  def send_text_message(phone_number, message)
    response = api_client.send_text(
      number: phone_number,
      text: apply_outbound_text(message.outgoing_content, message),
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay,
      **delivery_options(phone_number, message)
    )
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def send_location_message(phone_number, message)
    attachment = message.attachments.first
    response = api_client.send_location(
      number: phone_number,
      latitude: attachment.coordinates_lat,
      longitude: attachment.coordinates_long,
      name: attachment.fallback_title.presence,
      quoted: build_quoted_context(phone_number, message),
      delay: outbound_delay,
      **delivery_options(phone_number, message)
    )
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def location_attachment?(message)
    message.attachments.one? && message.attachments.first.location?
  end

  def send_input_select_message(phone_number, message)
    items = input_select_items(message)
    quoted = build_quoted_context(phone_number, message)
    delay = outbound_delay
    title = apply_outbound_text(message.outgoing_content.presence || 'Please choose an option', message)

    response = dispatch_input_select(phone_number, title, items, quoted, delay, message)
    message_id = process_response(response, message)
    mark_incoming_read_after_reply(phone_number, message) if message_id.present?
    message_id
  end

  def extract_source_id(parsed)
    return unless parsed.is_a?(Hash)

    data = parsed['data']
    return unless data.is_a?(Hash)

    info = Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(data, 'Info')
    (info.is_a?(Hash) ? info['ID'] || info['Id'] : nil) ||
      Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(data, 'messageId', 'MessageId')
  end

  def connection_open?
    response = api_client.connection_status
    return false unless response.success?

    data = api_client.unwrap(response, context: 'connection_status')
    connected = ActiveModel::Type::Boolean.new.cast(api_client.dig_field(data, 'connected', 'Connected'))
    logged_in = ActiveModel::Type::Boolean.new.cast(api_client.dig_field(data, 'loggedIn', 'LoggedIn'))
    connected && logged_in
  end

  def send_templates_as_text?
    ActiveModel::Type::Boolean.new.cast((whatsapp_channel.provider_config || {})['send_templates_as_text'])
  end

  def connection_validation_cache_key
    "evolution_go:validate_config:#{whatsapp_channel.id}"
  end

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(whatsapp_channel)
  end

  def fail_message_with_network_error!(message, error)
    error_text = error.respond_to?(:user_message) ? error.user_message : error.message
    Rails.logger.error(
      "[EVOLUTION_GO] send_message network error channel=#{whatsapp_channel.id} message=#{message&.id}: #{error.message}"
    )
    return if message.blank?

    message.external_error = error_text
    message.status = :failed
    message.save!
    create_send_error_private_note!(message, error_text) if notify_send_errors_private?
  end

  def session_disconnected?(text)
    Custom::Whatsapp::EvolutionGo::ApiError.session_disconnected?(text)
  end
end
