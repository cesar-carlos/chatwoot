# frozen_string_literal: true

module Custom::Api::V1::Accounts::InboxesController
  extend ActiveSupport::Concern

  def wavoip_sdk_bootstrap
    authorize @inbox, :show?
    channel = @inbox.channel
    return head :not_found unless wavoip_channel_ready?(channel)

    render json: { device_token: channel.device_token }
  end

  def wavoip_device_status
    authorize @inbox, :show?
    channel = @inbox.channel
    return head :not_found unless wavoip_channel_ready?(channel)

    force = ActiveModel::Type::Boolean.new.cast(params[:force])
    payload = Wavoip::DeviceStatusService.new(channel: channel).connection_payload(force: force)
    # Only bust account cache when all_info refreshed DB — not on 5s poll cache hits.
    @inbox.update_account_cache if payload[:refreshed]
    render json: payload
  end

  def wavoip_logout
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless wavoip_channel_ready?(channel)

    Wavoip::DeviceStatusService.new(channel: channel).logout!
    @inbox.update_account_cache
    render json: Wavoip::DeviceStatusService.new(channel: channel.reload).connection_payload(force: true)
  rescue Wavoip::DeviceStatusService::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def wavoip_qr
    refresh = ActiveModel::Type::Boolean.new.cast(params[:refresh])
    authorize @inbox, refresh ? :update? : :show?
    channel = @inbox.channel
    return head :not_found unless wavoip_channel_ready?(channel)

    payload = Wavoip::DeviceStatusService.new(channel: channel).qr_payload(refresh: refresh)
    @inbox.update_account_cache if payload[:live]
    render json: payload
  rescue Wavoip::DeviceStatusService::ApiError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def regenerate_wavoip_webhook_key
    authorize @inbox, :regenerate_wavoip_webhook_key?
    channel = @inbox.channel
    return head :not_found unless channel.is_a?(Channel::Wavoip)

    channel.regenerate_webhook_key!
    @inbox.update_account_cache
    render json: { wavoip_webhook_url: channel.webhook_url }
  end

  def test_wavoip_webhook
    authorize @inbox, :regenerate_wavoip_webhook_key?
    channel = @inbox.channel
    return head :not_found unless channel.is_a?(Channel::Wavoip)

    # Run inline so the response reflects verification + last_webhook_at immediately.
    Wavoip::ProcessWebhookJob.perform_now(
      @inbox.id,
      {
        'type' => 'DEVICE',
        'status' => 'open',
        'phone' => channel.phone_number
      }
    )
    channel.reload
    @inbox.update_account_cache
    render json: {
      ok: true,
      webhook_verified: channel.webhook_verified?
    }
  end

  def evolution_connection
    # Connection status/QR/pairing code is sensitive (it can be used to pair
    # a new phone as the account's WhatsApp) — keep it admin-only, matching
    # every other Evolution connection action (reconnect/logout/restart) and
    # the ActionCable channel that streams the same data.
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    payload = Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).connection_payload
    render json: payload
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] evolution_connection failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_reconnect
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).reconnect!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] evolution_reconnect failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_logout
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).logout!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] evolution_logout failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_restart
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).restart!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] evolution_restart failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_import
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ImportJob.perform_later(channel.id, force: true)
    render json: import_payload_for(channel.reload)
  end

  def evolution_refresh_contacts
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    result = Custom::Whatsapp::Evolution::ContactsRefreshService.new(channel: channel).perform
    render json: result
  rescue Custom::Whatsapp::Evolution::ContactsRefreshService::AlreadyRunningError => e
    status = Custom::Whatsapp::Evolution::ContactsRefreshService.lock_status(channel)
    render json: {
      error: e.message,
      code: 'already_running',
      remaining_seconds: status[:remaining_seconds]
    }, status: :unprocessable_entity
  end

  def evolution_go_connection
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    payload = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel).connection_payload(
      include_qr: ActiveModel::Type::Boolean.new.cast(params[:include_qr])
    )
    render json: payload
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.error "[EVOLUTION_GO] evolution_go_connection failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_go_reconnect
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
    service.reconnect!
    render json: service.connection_payload
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.error "[EVOLUTION_GO] evolution_go_reconnect failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_go_logout
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
    service.logout!
    render json: service.connection_payload
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.error "[EVOLUTION_GO] evolution_go_logout failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_go_import
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    Custom::Whatsapp::EvolutionGo::ImportJob.perform_later(channel.id, force: true)
    render json: import_payload_for(channel.reload)
  end

  def evolution_go_refresh_contacts
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    result = Custom::Whatsapp::EvolutionGo::ContactsRefreshService.new(channel: channel).perform
    render json: result
  rescue Custom::Whatsapp::EvolutionGo::ContactsRefreshService::AlreadyRunningError => e
    status = Custom::Whatsapp::EvolutionGo::ContactsRefreshService.lock_status(channel)
    render json: {
      error: e.message,
      code: 'already_running',
      remaining_seconds: status[:remaining_seconds]
    }, status: :unprocessable_entity
  end

  def evolution_go_diagnostics
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    render json: Custom::Whatsapp::EvolutionGo::DiagnosticsService.new(channel: channel).perform
  end

  def evolution_go_test_webhook
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    render json: Custom::Whatsapp::EvolutionGo::WebhookTestService.new(channel: channel).perform
  rescue StandardError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  def evolution_go_sync_webhook
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
    events = service.webhook_subscribe_sync.sync!
    render json: Custom::Whatsapp::EvolutionGo::DiagnosticsService.new(channel: channel.reload).perform.merge(
      webhook_subscribe: events
    )
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.error "[EVOLUTION_GO] evolution_go_sync_webhook failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_go_pair
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_go_channel?(channel)

    service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
    pairing = service.pair!(phone: params.require(:phone))
    render json: service.connection_payload.merge(pairing)
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.error "[EVOLUTION_GO] evolution_go_pair failed: #{e.log_message}"
    render json: { error: e.user_message }, status: :unprocessable_entity
  end

  def evolution_go_server_check
    authorize Inbox, :create?

    base_url = params.require(:base_url)
    unless Custom::Whatsapp::EvolutionGo::UrlSafetyGuard.safe?(base_url)
      return render json: { ok: false, error: 'Evolution Go server unreachable' },
                    status: :unprocessable_entity
    end

    client = Custom::Whatsapp::EvolutionGo::ApiClient.new(
      base_url: base_url,
      global_api_key: params[:global_api_key]
    )
    response = client.server_ok
    unless response.success?
      return render json: { ok: false, error: 'Evolution Go server unreachable' },
                    status: :unprocessable_entity
    end

    render json: { ok: true }
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    render json: { ok: false, error: e.user_message }, status: :unprocessable_entity
  end

  # FORK: move all conversation history from this WhatsApp inbox to another
  def move_history
    authorize @inbox, :update?
    target_inbox = Current.account.inboxes.find_by(id: params[:target_inbox_id])
    if target_inbox.blank?
      return render json: { error: 'target inbox not found', code: 'target_not_found' },
                    status: :unprocessable_entity
    end

    authorize target_inbox, :update?

    Custom::Inboxes::HistoryMigration::CompatibilityGuard.new(source: @inbox, target: target_inbox).validate!
    migration = InboxHistoryMigration.create!(
      account: Current.account,
      source_inbox: @inbox,
      target_inbox: target_inbox,
      requested_by: Current.user,
      status: 'pending'
    )
    Custom::Inboxes::HistoryMigrationJob.perform_later(migration.id)
    render json: migration_payload(migration)
  rescue Custom::Inboxes::HistoryMigration::CompatibilityGuard::Error => e
    render json: { error: e.message, code: e.code }, status: :unprocessable_entity
  end

  def move_history_status
    authorize @inbox, :update?
    migration = InboxHistoryMigration.where(source_inbox_id: @inbox.id).order(created_at: :desc).first
    return render json: {} if migration.blank?

    # Unblock UI when the worker died without completing (stale pending/running).
    migration.expire_if_stale!
    render json: migration_payload(migration.reload)
  end

  def update
    super
    refresh_evolution_channel_after_update!
  end

  private

  def refresh_evolution_channel_after_update!
    channel = @inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.evolution_provider?

    channel.reload
  end

  def evolution_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
  end

  def evolution_go_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution_go'
  end

  def connection_payload_for(channel)
    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).connection_payload
  end

  def import_payload_for(channel)
    config = channel.provider_config || {}
    {
      import_status: config['import_status'],
      import_stats: config['import_stats'] || {},
      import_error: config['import_error'],
      import_started_at: config['import_started_at'],
      import_completed_at: config['import_completed_at']
    }
  end

  def migration_payload(migration)
    {
      id: migration.id,
      status: migration.status,
      stats: migration.stats || {},
      error_message: migration.error_message,
      source_inbox_id: migration.source_inbox_id,
      target_inbox_id: migration.target_inbox_id,
      started_at: migration.started_at,
      heartbeat_at: migration.heartbeat_at,
      completed_at: migration.completed_at,
      created_at: migration.created_at
    }
  end

  def create
    return create_evolution_go_whatsapp_inbox! if evolution_go_whatsapp_channel?
    return super unless evolution_whatsapp_channel?

    validate_evolution_instance_name_available!

    channel = nil
    ActiveRecord::Base.transaction do
      channel = create_evolution_whatsapp_channel
      @inbox = Current.account.inboxes.build(
        {
          name: inbox_name(channel),
          channel: channel
        }.merge(permitted_params.except(:channel))
      )
      @inbox.save!
    end

    provision_evolution_channel!(channel)
  rescue StandardError => e
    render_evolution_create_error(e)
  end

  def render_evolution_create_error(error)
    case error
    when Custom::Whatsapp::Evolution::ApiError
      Rails.logger.error "[EVOLUTION] inbox create failed: #{error.log_message}"
      render json: { message: error.user_message }, status: :unprocessable_entity
    when ActiveRecord::RecordInvalid
      render json: { message: error.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
    when ActiveRecord::RecordNotUnique
      render json: { message: 'An Evolution inbox with this instance name already exists' },
             status: :unprocessable_entity
    else
      Rails.logger.error "[EVOLUTION] inbox create failed: #{error.class} #{error.message}"
      render json: { message: evolution_provision_error_message(error) }, status: :unprocessable_entity
    end
  end

  def create_channel
    return create_wavoip_channel if permitted_params[:channel][:type] == 'wavoip'
    return create_evolution_whatsapp_channel if evolution_whatsapp_channel?
    return create_evolution_go_whatsapp_channel if evolution_go_whatsapp_channel?

    super
  end

  def allowed_channel_types
    super + ['wavoip']
  end

  def evolution_whatsapp_channel?
    channel_params = params[:channel]
    return false if channel_params.blank?

    channel_params[:type].to_s == 'whatsapp' && channel_params[:provider].to_s == 'evolution'
  end

  def evolution_go_whatsapp_channel?
    channel_params = params[:channel]
    return false if channel_params.blank?

    channel_params[:type].to_s == 'whatsapp' && channel_params[:provider].to_s == 'evolution_go'
  end

  def evolution_provision_error_message(error)
    message = error.message.to_s
    return 'An Evolution inbox with this instance name already exists' if message.include?('index_channel_whatsapp_evolution_instance_name')

    message.presence || 'Failed to provision Evolution instance'
  end

  def create_evolution_whatsapp_channel
    config = build_evolution_provider_config

    channel = Current.account.whatsapp_channels.new(
      provider: 'evolution',
      phone_number: evolution_placeholder_phone,
      provider_config: config.merge(
        'connection_status' => Custom::Whatsapp::Evolution::ProviderConfig::PENDING_PROVISION_STATUS
      )
    )
    channel.save!(validate: false)
    channel
  end

  def build_evolution_provider_config
    evolution_params = evolution_channel_params

    Custom::Whatsapp::Evolution::ProviderConfig.normalize_credentials(
      Custom::Whatsapp::Evolution::ProviderConfig.build(
        'base_url' => evolution_params[:base_url],
        'instance_name' => evolution_params[:instance_name],
        'api_key' => evolution_params[:api_key]
      ).merge((evolution_params[:provider_config] || {}).stringify_keys)
    )
  end

  def validate_evolution_instance_name_available!
    instance_name = evolution_channel_params[:instance_name].to_s.strip
    return if instance_name.blank?

    return unless evolution_instance_name_taken?(instance_name)

    raise Custom::Whatsapp::Evolution::ApiError.new(
      'An Evolution inbox with this instance name already exists',
      status: 422
    )
  end

  def evolution_instance_name_taken?(instance_name)
    Channel::Whatsapp
      .where(provider: 'evolution')
      .exists?(["provider_config->>'instance_name' = ?", instance_name])
  end

  def evolution_channel_params
    params.require(:channel).permit(
      :base_url,
      :api_key,
      :instance_name,
      provider_config: [
        :proxy_enabled,
        :proxy_host,
        :proxy_port,
        :proxy_protocol,
        :proxy_username,
        :proxy_password
      ]
    )
  end

  def provision_evolution_channel!(channel)
    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).provision_new_instance!
  rescue StandardError
    cleanup_failed_evolution_channel!(channel)
    raise
  end

  def cleanup_failed_evolution_channel!(channel)
    channel.inbox&.destroy!
    channel.destroy! if channel.persisted?
  end

  def evolution_placeholder_phone
    loop do
      phone = "+55000#{SecureRandom.hex(5)}"
      break phone unless Channel::Whatsapp.exists?(phone_number: phone)
    end
  end

  def create_evolution_go_whatsapp_inbox!
    validate_evolution_go_instance_name_available!

    channel = nil
    ActiveRecord::Base.transaction do
      channel = create_evolution_go_whatsapp_channel
      @inbox = Current.account.inboxes.build(
        {
          name: inbox_name(channel),
          channel: channel
        }.merge(permitted_params.except(:channel))
      )
      @inbox.save!
    end

    provision_evolution_go_channel!(channel)
  rescue StandardError => e
    render_evolution_go_create_error(e)
  end

  def render_evolution_go_create_error(error)
    case error
    when Custom::Whatsapp::EvolutionGo::ApiError
      Rails.logger.error "[EVOLUTION_GO] inbox create failed: #{error.log_message}"
      render json: { message: error.user_message }, status: :unprocessable_entity
    when ActiveRecord::RecordInvalid
      render json: { message: error.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
    when ActiveRecord::RecordNotUnique
      render json: { message: 'An Evolution Go inbox with this instance name already exists' },
             status: :unprocessable_entity
    else
      Rails.logger.error "[EVOLUTION_GO] inbox create failed: #{error.class} #{error.message}"
      render json: { message: evolution_go_provision_error_message(error) }, status: :unprocessable_entity
    end
  end

  def evolution_go_provision_error_message(error)
    message = error.message.to_s
    return 'An Evolution Go inbox with this instance name already exists' if message.include?('index_channel_whatsapp_evolution_go_instance_name')

    message.presence || 'Failed to provision Evolution Go instance'
  end

  def create_evolution_go_whatsapp_channel
    config = build_evolution_go_provider_config

    channel = Current.account.whatsapp_channels.new(
      provider: 'evolution_go',
      phone_number: evolution_placeholder_phone,
      provider_config: config.merge(
        'connection_status' => Custom::Whatsapp::EvolutionGo::ProviderConfig::PENDING_PROVISION_STATUS
      )
    )
    channel.save!(validate: false)
    channel
  end

  def build_evolution_go_provider_config
    go_params = evolution_go_channel_params

    Custom::Whatsapp::EvolutionGo::ProviderConfig.normalize_credentials(
      Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'base_url' => go_params[:base_url],
        'global_api_key' => go_params[:global_api_key],
        'instance_name' => go_params[:instance_name],
        'instance_token' => go_params[:instance_token]
      ).merge((go_params[:provider_config] || {}).stringify_keys)
    )
  end

  def validate_evolution_go_instance_name_available!
    instance_name = evolution_go_channel_params[:instance_name].to_s.strip
    return if instance_name.blank?

    return unless evolution_go_instance_name_taken?(instance_name)

    raise Custom::Whatsapp::EvolutionGo::ApiError.new(
      'An Evolution Go inbox with this instance name already exists',
      status: 422
    )
  end

  def evolution_go_instance_name_taken?(instance_name)
    Channel::Whatsapp
      .where(provider: 'evolution_go')
      .exists?(["provider_config->>'instance_name' = ?", instance_name])
  end

  def evolution_go_channel_params
    params.require(:channel).permit(
      :base_url,
      :global_api_key,
      :instance_name,
      :instance_token,
      provider_config: %i[
        proxy_enabled
        proxy_host
        proxy_port
        proxy_username
        proxy_password
      ]
    )
  end

  def provision_evolution_go_channel!(channel)
    service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: channel)
    if channel.provider_config['instance_token'].present?
      service.connect_existing_inbox!
    else
      service.provision_new_inbox!
    end
  rescue StandardError
    cleanup_failed_evolution_channel!(channel)
    raise
  end

  def channel_type_from_params
    return Channel::Wavoip if permitted_params[:channel][:type] == 'wavoip'

    super
  end

  def account_channels_method
    return Current.account.wavoip_channels if permitted_params[:channel][:type] == 'wavoip'

    super
  end

  def create_wavoip_channel
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('channel_voice') && Current.account.feature_enabled?('channel_wavoip')

    wavoip_params = params.require(:channel).permit(
      :phone_number,
      :device_token,
      provider_config: %i[
        inbound_calls_enabled
        call_recording_enabled
        incoming_call_include_administrators
        incoming_call_offline_fallback
        incoming_call_notify_busy_agents
        ring_timeout_seconds
      ]
    )

    Current.account.wavoip_channels.create!(wavoip_params)
  end

  def wavoip_channel_ready?(channel)
    channel.is_a?(Channel::Wavoip) && channel.voice_enabled?
  end
end
