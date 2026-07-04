# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ConnectionService
  include Custom::Whatsapp::EvolutionGo::SettingsSync

  CONNECTION_STATE_CACHE_TTL = 15.seconds

  pattr_initialize [:channel!]

  def teardown!
    provisioner.teardown!
  end

  def provision_new_inbox!
    provisioner.provision_new_inbox!
  end

  def connect_existing_inbox!
    provisioner.connect_existing_inbox!
  end

  def handle_event(envelope)
    connection_events.handle_event(envelope)
  end

  def reconnect!
    update_runtime_config!('connection_status' => 'connecting')
    invalidate_connection_state_cache!
    provisioner.connect_existing_inbox!
  end

  def sync_phone_number!
    response = api_client.connection_status
    return unless response.success?

    data = api_client.unwrap(response)
    jid = api_client.dig_field(data, 'jid', 'myJid', 'JID', 'MyJid')
    phone = phone_from_jid(jid)
    update_phone_number!(phone) if phone.present? && placeholder_phone?(channel.phone_number)
  end

  def connection_payload
    refresh_connection_status!
    fetch_qr_if_needed!
    {
      connection_status: provider_config['connection_status'],
      phone_number: channel.phone_number,
      qrcode_base64: provider_config['last_qr_base64'],
      qrcode_code: provider_config['last_qr_code']
    }
  end

  def broadcast_connection_event(payload)
    inbox_id = channel.inbox&.id
    return if inbox_id.blank?

    ActionCable.server.broadcast(
      "evolution_go:connection:#{inbox_id}",
      payload.stringify_keys
    )
  end

  def update_connection_status(state)
    normalized = normalize_connection_status(state)
    return if normalized.blank?

    invalidate_connection_state_cache!
    update_runtime_config!('connection_status' => normalized)
    invalidate_connection_validation_cache! if channel.respond_to?(:provider_service)
    sync_phone_number! if normalized == 'open'
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

  def connection_events
    @connection_events ||= Custom::Whatsapp::EvolutionGo::ConnectionEvents.new(
      channel: channel,
      connection_service: self
    )
  end

  protected

  def refresh_connection_status!
    cache_key = connection_state_cache_key
    return if Rails.cache.read(cache_key).present?

    response = api_client.connection_status
    unless response.success?
      Rails.logger.warn(
        "[EVOLUTION_GO] connection_status failed channel=#{channel.id} status=#{response.code}"
      )
      return
    end

    data = api_client.unwrap(response)
    connected = ActiveModel::Type::Boolean.new.cast(api_client.dig_field(data, 'connected', 'Connected'))
    logged_in = ActiveModel::Type::Boolean.new.cast(api_client.dig_field(data, 'loggedIn', 'LoggedIn'))
    state = connected && logged_in ? 'open' : (connected ? 'connecting' : 'close')
    update_connection_status(state)
    Rails.cache.write(cache_key, true, expires_in: CONNECTION_STATE_CACHE_TTL)
  end

  private

  def provisioner
    @provisioner ||= Custom::Whatsapp::EvolutionGo::ConnectionProvisioner.new(
      channel: channel,
      connection_service: self
    )
  end

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def provider_config
    channel.provider_config || {}
  end

  def fetch_qr_if_needed!
    return unless provider_config['connection_status'].in?(%w[connecting close])
    return if provider_config['last_qr_base64'].present?

    provisioner.send(:fetch_qr_code!)
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn "[EVOLUTION_GO] fetch_qr_if_needed failed channel=#{channel.id}: #{e.message}"
  end

  def normalize_connection_status(state)
    case state.to_s.downcase
    when 'open', 'connected' then 'open'
    when 'connecting' then 'connecting'
    when 'close', 'closed', 'disconnected' then 'close'
    end
  end

  def phone_from_jid(jid)
    digits = jid.to_s.split('@').first
    return if digits.blank?

    "+#{digits.gsub(/\D/, '')}"
  end

  def placeholder_phone?(phone)
    phone.to_s.start_with?('+55000')
  end

  def update_phone_number!(phone)
    channel.update_columns(phone_number: phone, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    channel.phone_number = phone
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.warn(
      "[EVOLUTION_GO] phone #{phone} already in use; keeping current number for channel #{channel.id}"
    )
  end

  def connection_state_cache_key
    "evolution_go:connection_state:#{channel.id}"
  end

  def invalidate_connection_state_cache!
    Rails.cache.delete(connection_state_cache_key)
  end

  def invalidate_connection_validation_cache!
    Rails.cache.delete("evolution_go:validate_config:#{channel.id}")
  end
end
