# frozen_string_literal: true

class Custom::Whatsapp::Evolution::Provisioner
  pattr_initialize [:channel!, :connection_service!]

  def provision_new_instance!
    validate_webhook_base_url!

    instance_created = false

    response = api_client.create_instance(create_instance_body)
    raise_api_error!(response, 'Failed to create Evolution instance')
    instance_created = true

    provision_post_create!(response.parsed_response)
  rescue Custom::Whatsapp::Evolution::ApiError, StandardError => e
    delete_remote_instance! if instance_created
    raise e
  end

  def provision_post_create!(parsed)
    persist_instance_credentials!(parsed)
    register_webhook!
    sync_settings!
    sync_proxy! if proxy_enabled?
    ensure_chatwoot_integration_disabled!
    connection_service.fetch_qr_code
  end

  def register_webhook!
    response = api_client.apply_webhook(webhook_url)
    raise_api_error!(response, 'Failed to register Evolution webhook')
  end

  def sync_settings!
    response = api_client.apply_settings(settings_payload)
    raise_api_error!(response, 'Failed to sync Evolution settings')
  end

  def sync_proxy!
    response = api_client.apply_proxy(proxy_payload)
    raise_api_error!(response, 'Failed to configure Evolution proxy')
  end

  def ensure_chatwoot_integration_disabled!
    api_client.disable_chatwoot_integration
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] disable chatwoot integration: #{e.message}"
  end

  def delete_remote_instance!
    response = api_client.delete_instance
    return if response.success?

    Rails.logger.warn(
      "[EVOLUTION] failed to delete instance #{provider_config['instance_name']}: HTTP #{response.code}"
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] delete instance error: #{e.message}"
  end

  private

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end

  def provider_config
    channel.provider_config || {}
  end

  def create_instance_body
    create_instance_base_body.tap do |body|
      merge_proxy_credentials!(body) if proxy_enabled? && provider_config['proxy_host'].present?
    end
  end

  def create_instance_base_body
    {
      instanceName: provider_config['instance_name'],
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true,
      groupsIgnore: provider_config['groups_ignore'],
      rejectCall: provider_config['reject_call'],
      alwaysOnline: provider_config['always_online'],
      readMessages: provider_config['read_messages'],
      readStatus: provider_config['read_status'],
      syncFullHistory: provider_config['sync_full_history']
    }
  end

  def merge_proxy_credentials!(body)
    body.merge!(
      proxyHost: provider_config['proxy_host'],
      proxyPort: provider_config['proxy_port'].to_s,
      proxyProtocol: provider_config['proxy_protocol'],
      proxyUsername: provider_config['proxy_username'],
      proxyPassword: provider_config['proxy_password']
    )
  end

  def settings_payload
    {
      rejectCall: provider_config['reject_call'],
      msgCall: provider_config['msg_call'],
      groupsIgnore: provider_config['groups_ignore'],
      alwaysOnline: provider_config['always_online'],
      readMessages: provider_config['read_messages'],
      readStatus: provider_config['read_status'],
      syncFullHistory: provider_config['sync_full_history']
    }
  end

  def proxy_payload
    connection_service.send(:proxy_payload)
  end

  def proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(provider_config['proxy_enabled'])
  end

  def validate_webhook_base_url!
    return if ENV.fetch('FRONTEND_URL', nil).present?

    raise Custom::Whatsapp::Evolution::ApiError,
          'FRONTEND_URL is not configured; cannot register Evolution webhook'
  end

  def webhook_url
    base = ENV.fetch('FRONTEND_URL', nil).to_s.delete_suffix('/')
    "#{base}/webhooks/evolution/#{provider_config['instance_name']}"
  end

  def persist_instance_credentials!(parsed)
    instance = parsed['instance'] || {}
    attrs = {
      'api_key' => (parsed['hash'] || provider_config['api_key']).to_s.strip,
      'instance_id' => instance['instanceId'],
      'connection_status' => instance['status'] || 'connecting'
    }
    merged = provider_config.merge(attrs.stringify_keys)
    channel.provider_config = merged
    connection_service.send(:persist_provider_config!, merged)
    @api_client = nil
  end

  def raise_api_error!(response, message)
    return if response.success?

    error = Custom::Whatsapp::Evolution::ApiError.new(
      message,
      status: response.code,
      body: response.parsed_response
    )
    Rails.logger.warn "[EVOLUTION] #{error.message} (HTTP #{response.code})"
    raise error
  end
end
