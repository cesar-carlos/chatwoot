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
    update_runtime_config!(
      'connection_status' => 'connecting',
      'last_qr_base64' => nil,
      'last_qr_code' => nil
    )
    invalidate_connection_state_cache!
    disconnect_before_reconnect!
    provisioner.connect_existing_inbox!
  end

  def logout!
    response = api_client.logout
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(response, 'Failed to logout Evolution Go instance')

    invalidate_connection_state_cache!
    update_runtime_config!(
      'connection_status' => 'close',
      'last_qr_base64' => nil,
      'last_qr_code' => nil
    )
    invalidate_connection_validation_cache! if channel.respond_to?(:provider_service)
    response.parsed_response
  end

  def sync_phone_number!
    response = api_client.connection_status
    return unless response.success?

    data = api_client.unwrap(response, context: 'connection_status')
    jid = api_client.dig_field(data, 'jid', 'myJid', 'JID', 'MyJid')
    sync_phone_from_jid!(jid)
  end

  def sync_phone_from_jid!(jid)
    phone = phone_from_jid(jid)
    update_phone_number!(phone) if phone.present? && placeholder_phone?(channel.phone_number)
  end

  def connection_payload
    state_checked = refresh_connection_status!
    fetch_qr_if_needed!(state_checked: state_checked)
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

    previous_status = provider_config['connection_status']
    attrs = { 'connection_status' => normalized }
    if normalized == 'close'
      attrs['last_qr_base64'] = nil
      attrs['last_qr_code'] = nil
    end

    invalidate_connection_state_cache!
    update_runtime_config!(attrs)
    invalidate_connection_validation_cache! if channel.respond_to?(:provider_service)
    sync_phone_number! if normalized == 'open'
    maybe_enqueue_contacts_import!(previous_status, normalized) if normalized == 'open'
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
    return :cached if Rails.cache.read(cache_key).present?

    response = api_client.connection_status
    unless response.success?
      Rails.logger.warn(
        "[EVOLUTION_GO] connection_status failed channel=#{channel.id} status=#{response.code}"
      )
      return :failed
    end

    data = api_client.unwrap(response, context: 'connection_status')
    update_connection_status(connection_state_from_status_data(data))
    Rails.cache.write(cache_key, true, expires_in: CONNECTION_STATE_CACHE_TTL)
    :success
  end

  def connection_state_from_status_data(data)
    connected = ActiveModel::Type::Boolean.new.cast(api_client.dig_field(data, 'connected', 'Connected'))
    logged_in = ActiveModel::Type::Boolean.new.cast(api_client.dig_field(data, 'loggedIn', 'LoggedIn'))
    return 'open' if connected && logged_in

    connected ? 'connecting' : 'close'
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

  def fetch_qr_if_needed!(state_checked: nil)
    return unless provider_config['connection_status'].in?(%w[connecting close])
    return if provider_config['last_qr_base64'].present?
    return if state_checked == :failed

    provisioner.send(:fetch_qr_code!)
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn "[EVOLUTION_GO] fetch_qr_if_needed failed channel=#{channel.id}: #{e.message}"
  end

  def disconnect_before_reconnect!
    api_client.disconnect
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.warn "[EVOLUTION_GO] disconnect before reconnect failed channel=#{channel.id}: #{e.message}"
  end

  def normalize_connection_status(state)
    case state.to_s.downcase
    when 'open', 'connected' then 'open'
    when 'connecting' then 'connecting'
    when 'close', 'closed', 'disconnected' then 'close'
    end
  end

  def phone_from_jid(jid)
    phone = jid_resolver.phone_from_jid(jid)
    return if phone.blank?

    "+#{phone}"
  end

  def jid_resolver
    @jid_resolver ||= Custom::Whatsapp::EvolutionGo::JidResolver.new(provider_config)
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

  def maybe_enqueue_contacts_import!(previous_status, state)
    return unless state == 'open'
    return if previous_status == 'open'
    return unless import_on_connect_enabled?
    return unless import_contacts_enabled?

    status = provider_config['import_status']
    return if status.in?(%w[running completed])

    Custom::Whatsapp::EvolutionGo::ImportJob.perform_later(channel.id)
  end

  def import_on_connect_enabled?
    ActiveModel::Type::Boolean.new.cast(provider_config['import_on_connect'])
  end

  def import_contacts_enabled?
    ActiveModel::Type::Boolean.new.cast(provider_config['import_contacts'])
  end
end
