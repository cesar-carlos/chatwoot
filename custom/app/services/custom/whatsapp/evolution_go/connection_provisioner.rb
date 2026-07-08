# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ConnectionProvisioner
  QR_FETCH_MAX_ATTEMPTS = 3
  QR_FETCH_DELAY_SECONDS = 1.0

  pattr_initialize [:channel!, :connection_service!]

  def self.webhook_url_for(channel)
    config = (channel.provider_config || {}).stringify_keys
    base = ENV.fetch('FRONTEND_URL', nil).to_s.delete_suffix('/')
    token = CGI.escape(config['webhook_token'].to_s)
    "#{base}/webhooks/evolution_go/#{config['instance_name']}?token=#{token}"
  end

  def provision_new_inbox!
    validate_webhook_base_url!

    instance_created = false
    response = api_client.create_instance(name: provider_config['instance_name'], proxy: proxy_body)
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(response, 'Failed to create Evolution Go instance')
    instance_created = true

    persist_create_response!(response)
    connect_with_webhook!
  rescue StandardError => e
    delete_remote_instance! if instance_created
    raise e
  end

  def connect_existing_inbox!
    validate_webhook_base_url!
    ensure_webhook_token!
    connect_with_webhook!
  end

  def teardown!
    instance_id = provider_config['instance_id']
    return if instance_id.blank?

    response = api_client.delete_instance(instance_id)
    return if response.success?

    Rails.logger.warn(
      "[EVOLUTION_GO] failed to delete instance #{provider_config['instance_name']}: HTTP #{response.code}"
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION_GO] delete instance error: #{e.message}"
  end

  private

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def provider_config
    channel.provider_config || {}
  end

  def persist_create_response!(response) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    data = api_client.unwrap(response, context: 'create_instance')
    token = api_client.dig_field(data, 'token', 'Token').to_s.strip
    instance_id = api_client.dig_field(data, 'id', 'Id', 'ID').to_s
    if token.blank? || instance_id.blank?
      raise Custom::Whatsapp::EvolutionGo::ApiError.new(
        'Evolution Go create response missing instance token or id',
        status: response.code,
        body: response.parsed_response
      )
    end

    attrs = {
      'instance_token' => token,
      'instance_id' => instance_id,
      'instance_name' => api_client.dig_field(data, 'name', 'Name') || provider_config['instance_name'],
      'connection_status' => 'connecting',
      'webhook_token' => provider_config['webhook_token'].presence || SecureRandom.hex(16),
      'webhook_subscribe' => provider_config['webhook_subscribe'].presence ||
                             Custom::Whatsapp::EvolutionGo::WebhookSubscribeSync.canonical_events(provider_config)
    }
    connection_service.persist_provider_config!(provider_config.merge(attrs.stringify_keys))
    @api_client = nil
  end

  def ensure_webhook_token!
    return if provider_config['webhook_token'].present?

    connection_service.update_runtime_config!('webhook_token' => SecureRandom.hex(16))
  end

  def connect_with_webhook!
    Custom::Whatsapp::EvolutionGo::WebhookSubscribeSync.new(
      channel: channel,
      connection_service: connection_service
    ).sync!
  end

  def fetch_qr_code!(raise_on_failure: true, max_attempts: QR_FETCH_MAX_ATTEMPTS)
    last_error = nil
    attempts = [max_attempts.to_i, 1].max

    attempts.times do |attempt|
      response = api_client.qr_code
      if response.success?
        attrs = qr_storage_attrs_from_response(response)
        if attrs.present?
          connection_service.update_runtime_config!(attrs)
          return true
        end

        last_error = transient_qr_unavailable_error(response)
      elsif qr_fetch_retryable?(response)
        last_error = qr_api_error(response)
      elsif raise_on_failure
        Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(response, 'Failed to fetch Evolution Go QR code')
      else
        last_error = qr_api_error(response)
      end

      sleep(QR_FETCH_DELAY_SECONDS) if attempt < attempts - 1
    end

    if raise_on_failure
      raise last_error || transient_qr_unavailable_error
    end

    Rails.logger.warn(
      "[EVOLUTION_GO] QR not ready after #{attempts} attempts channel=#{channel.id}: #{last_error&.message}"
    )
    false
  end

  def qr_storage_attrs_from_response(response)
    data = api_client.unwrap(response, context: 'qr_code')
    connection_service.connection_events.qrcode_storage_attrs(
      'qrcode' => api_client.dig_field(data, 'qrcode', 'Qrcode'),
      'code' => api_client.dig_field(data, 'code', 'Code')
    )
  end

  def qr_fetch_retryable?(response)
    status = response.code.to_i
    return true if status.in?([404, 422])

    qr_not_ready_message?(response.parsed_response)
  end

  def qr_not_ready_message?(body)
    message = Custom::Whatsapp::EvolutionGo::ApiError.extract_message(body)
    message.match?(/no QR code available|not ready|wait a moment/i)
  end

  def qr_api_error(response)
    Custom::Whatsapp::EvolutionGo::ApiError.new(
      'Failed to fetch Evolution Go QR code',
      status: response.code,
      body: response.parsed_response
    )
  end

  def transient_qr_unavailable_error(response = nil)
    Custom::Whatsapp::EvolutionGo::ApiError.new(
      'Failed to fetch Evolution Go QR code',
      status: response&.code || 422,
      body: response&.parsed_response || { 'message' => 'no QR code available. Please wait a moment and try again' }
    )
  end

  def delete_remote_instance!
    instance_id = provider_config['instance_id']
    return if instance_id.blank?

    api_client.delete_instance(instance_id)
  end

  def webhook_url
    base = ENV.fetch('FRONTEND_URL', nil).to_s.delete_suffix('/')
    token = CGI.escape(provider_config['webhook_token'].to_s)
    "#{base}/webhooks/evolution_go/#{provider_config['instance_name']}?token=#{token}"
  end

  def webhook_subscribe_events
    Custom::Whatsapp::EvolutionGo::WebhookSubscribeSync.new(
      channel: channel,
      connection_service: connection_service
    ).merge_stored!
  end

  def proxy_body
    return unless proxy_enabled?

    {
      host: provider_config['proxy_host'],
      port: provider_config['proxy_port'].to_s,
      username: provider_config['proxy_username'].to_s,
      password: provider_config['proxy_password'].to_s
    }
  end

  def proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(provider_config['proxy_enabled']) &&
      provider_config['proxy_host'].present?
  end

  def validate_webhook_base_url!
    return if ENV.fetch('FRONTEND_URL', nil).present?

    raise Custom::Whatsapp::EvolutionGo::ApiError,
          'FRONTEND_URL is not configured; cannot register Evolution Go webhook'
  end
end
