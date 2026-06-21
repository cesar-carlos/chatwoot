# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ConnectionService
  pattr_initialize [:channel!]

  def teardown!
    delete_remote_instance!
  end

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
    fetch_qr_code
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

  def fetch_qr_code
    response = api_client.connect
    raise_api_error!(response, 'Failed to fetch Evolution QR code') unless response.success?

    parsed = response.parsed_response
    qrcode = parsed['qrcode'] || parsed['base64']
    update_provider_config!(
      'last_qr_base64' => qrcode.is_a?(Hash) ? qrcode['base64'] : qrcode,
      'last_qr_code' => qrcode.is_a?(Hash) ? qrcode['code'] : nil
    )
    parsed
  end

  def reconnect!
    update_connection_status('connecting')
    fetch_qr_code
  end

  def logout!
    response = api_client.logout_instance
    raise_api_error!(response, 'Failed to logout Evolution instance')

    update_connection_status('close')
    response.parsed_response
  end

  def restart!
    response = api_client.restart_instance
    raise_api_error!(response, 'Failed to restart Evolution instance')

    update_connection_status('connecting')
    fetch_qr_code
    response.parsed_response
  end

  def refresh_connection_status!
    response = api_client.connection_state
    return unless response.success?

    state = response.parsed_response.dig('instance', 'state') ||
            response.parsed_response['state']
    update_connection_status(state) if state.present?
    response.parsed_response
  end

  def handle_event(envelope)
    envelope = envelope.with_indifferent_access
    case envelope[:event]
    when 'CONNECTION_UPDATE'
      handle_connection_update_event(envelope)
    when 'QRCODE_UPDATED'
      handle_qrcode_updated_event(envelope)
    end
  end

  def connection_payload
    refresh_connection_status!
    {
      connection_status: provider_config['connection_status'],
      phone_number: channel.phone_number,
      qrcode_base64: provider_config['last_qr_base64'],
      qrcode_code: provider_config['last_qr_code']
    }
  end

  private

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.new(
      base_url: provider_config['base_url'],
      api_key: provider_config['api_key'],
      instance_name: provider_config['instance_name']
    )
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

  PROXY_DISABLED_HOST = 'x'
  PROXY_DISABLED_PORT = '1'
  PROXY_DISABLED_PROTOCOL = 'http'

  def proxy_payload
    return disabled_proxy_payload unless proxy_enabled?

    {
      enabled: true,
      host: provider_config['proxy_host'],
      port: provider_config['proxy_port'].to_s,
      protocol: provider_config['proxy_protocol'],
      username: provider_config['proxy_username'],
      password: provider_config['proxy_password']
    }
  end

  def disabled_proxy_payload
    # Evolution JSON schema requires non-empty host/port/protocol even when enabled: false
    # (controller clears them after validation — see proxy.controller.ts).
    {
      enabled: false,
      host: provider_config['proxy_host'].presence || PROXY_DISABLED_HOST,
      port: provider_config['proxy_port'].presence || PROXY_DISABLED_PORT,
      protocol: provider_config['proxy_protocol'].presence || PROXY_DISABLED_PROTOCOL,
      username: provider_config['proxy_username'].to_s,
      password: provider_config['proxy_password'].to_s
    }
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
    # Skip credential validation mid-provision; connection is not ready for health checks yet.
    persist_provider_config!(merged)
    @api_client = nil
  end

  def update_connection_status(state)
    previous_status = provider_config['connection_status']
    update_runtime_config!('connection_status' => state)
    return unless state == 'open'

    phone = phone_from_sender(provider_config['last_sender'])
    update_phone_number!(phone) if phone.present? && placeholder_phone?(channel.phone_number)
    maybe_enqueue_history_import!(previous_status, state)
  end

  def extract_phone_number(envelope)
    sender = envelope[:sender].presence || envelope.dig(:data, :sender)
    return if sender.blank?

    update_runtime_config!('last_sender' => sender)
    return unless envelope.dig(:data, :state) == 'open'

    phone = phone_from_sender(sender)
    update_phone_number!(phone) if phone.present?
  end

  def phone_from_sender(sender)
    digits = sender.to_s.split('@').first
    return if digits.blank?

    "+#{digits.gsub(/\D/, '')}"
  end

  def placeholder_phone?(phone)
    phone.to_s.start_with?('+55000')
  end

  def update_provider_config!(attrs)
    attrs = attrs.stringify_keys
    merged = provider_config.merge(attrs)
    channel.provider_config = merged

    if Custom::Whatsapp::Evolution::ProviderConfig.runtime_only?(attrs)
      persist_provider_config!(merged)
    else
      channel.save!
    end
  end

  def update_runtime_config!(attrs)
    attrs = attrs.stringify_keys
    return if attrs.blank?

    persist_provider_config!(provider_config.merge(attrs))
  end

  def persist_provider_config!(merged)
    # Runtime keys must not re-run provider validations on every webhook poll.
    channel.update_columns(provider_config: merged, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    channel.provider_config = merged
  end

  def update_phone_number!(phone)
    channel.update_columns(phone_number: phone, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    channel.phone_number = phone
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.warn(
      "[EVOLUTION] phone #{phone} already in use; keeping current number for channel #{channel.id}"
    )
  end

  def notify_disconnection!(previous_status, state)
    return unless state == 'close' && previous_status != 'close'

    inbox = channel.inbox
    return if inbox.blank?

    Custom::Whatsapp::Evolution::Broadcaster.new(inbox: inbox).broadcast_disconnected
  end

  def broadcast_connection_event(payload)
    inbox = channel.inbox
    return if inbox.blank?

    ActionCable.server.broadcast(
      "evolution:connection:#{inbox.id}",
      payload.merge(inbox_id: inbox.id)
    )
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

  def handle_connection_update_event(envelope)
    state = envelope.dig(:data, :state)
    previous_status = provider_config['connection_status']
    update_connection_status(state)
    extract_phone_number(envelope)
    broadcast_connection_event(connection_event_payload(state))
    notify_disconnection!(previous_status, state)
  end

  def connection_event_payload(state)
    payload = { connection_status: state }
    payload[:phone_number] = channel.phone_number if state == 'open' && channel.phone_number.present?
    payload
  end

  def handle_qrcode_updated_event(envelope)
    qrcode = envelope[:data]
    attrs = qrcode_storage_attrs(qrcode)
    update_provider_config!(attrs) if attrs.present?
    broadcast_connection_event(qrcode: qrcode)
  end

  def qrcode_storage_attrs(qrcode)
    return {} unless qrcode.is_a?(Hash)

    base64 = qrcode.dig(:qrcode, :base64) || qrcode[:base64]
    code = qrcode.dig(:qrcode, :code) || qrcode[:code]
    attrs = {}
    attrs['last_qr_base64'] = base64 if base64.present?
    attrs['last_qr_code'] = code if code.present?
    attrs
  end

  def maybe_enqueue_history_import!(previous_status, state)
    return unless state == 'open'
    return if previous_status == 'open'
    return unless history_import_enabled?

    status = provider_config['import_status']
    return if status.in?(%w[running completed])

    Custom::Whatsapp::Evolution::ImportJob.perform_later(channel.id)
  end

  def history_import_enabled?
    cfg = provider_config
    ActiveModel::Type::Boolean.new.cast(cfg['import_contacts']) ||
      ActiveModel::Type::Boolean.new.cast(cfg['import_messages'])
  end
end
