# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ConnectionService
  pattr_initialize [:channel!]

  def teardown!
    provisioner.delete_remote_instance!
  end

  def provision_new_instance!
    provisioner.provision_new_instance!
  end

  def provision_post_create!(parsed)
    provisioner.provision_post_create!(parsed)
  end

  def register_webhook!
    provisioner.register_webhook!
  end

  def sync_settings!
    provisioner.sync_settings!
  end

  def sync_proxy!
    provisioner.sync_proxy!
  end

  def ensure_chatwoot_integration_disabled!
    provisioner.ensure_chatwoot_integration_disabled!
  end

  def fetch_qr_code
    response = api_client.connect
    raise_api_error!(response, 'Failed to fetch Evolution QR code') unless response.success?

    parsed = response.parsed_response
    qrcode_source = parsed['qrcode'].presence || parsed
    attrs = qrcode_storage_attrs(qrcode_source)
    update_provider_config!(attrs) if attrs.present?
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
    connection_events.handle_event(envelope)
  end

  def qrcode_storage_attrs(qrcode)
    connection_events.qrcode_storage_attrs(qrcode)
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

  def provisioner
    @provisioner ||= Custom::Whatsapp::Evolution::Provisioner.new(
      channel: channel,
      connection_service: self
    )
  end

  def connection_events
    @connection_events ||= Custom::Whatsapp::Evolution::ConnectionEvents.new(
      channel: channel,
      connection_service: self
    )
  end

  def api_client
    @api_client ||= Custom::Whatsapp::Evolution::ApiClient.for_channel(channel)
  end

  def provider_config
    channel.provider_config || {}
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
