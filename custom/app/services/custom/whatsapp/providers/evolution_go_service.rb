# frozen_string_literal: true

class Custom::Whatsapp::Providers::EvolutionGoService < Whatsapp::Providers::BaseService
  include Custom::Whatsapp::Providers::EvolutionGoServiceOutbound

  def send_message(phone_number, message)
    @message = message
    if message.attachments.present?
      send_attachment_message(phone_number, message)
    else
      send_text_message(phone_number, message)
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
    Rails.cache.write(connection_validation_cache_key, open, expires_in: 30.seconds)
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
    body = response.parsed_response
    return body.to_s unless body.is_a?(Hash)

    body.dig('error', 'message') || body['message'] || body['error']
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

  def extract_source_id(parsed)
    return unless parsed.is_a?(Hash)

    data = parsed['data'] || {}
    Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(data, 'Info')&.dig('ID') ||
      Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(data, 'messageId', 'MessageId') ||
      parsed.dig('data', 'Info', 'ID') ||
      parsed.dig('data', 'messageId')
  end

  def connection_open?
    response = api_client.connection_status
    return false unless response.success?

    data = api_client.unwrap(response)
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
    create_send_error_private_note!(message, nil) if notify_send_errors_private?
  end
end
