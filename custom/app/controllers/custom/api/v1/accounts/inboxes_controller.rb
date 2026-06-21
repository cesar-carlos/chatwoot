# frozen_string_literal: true

module Custom::Api::V1::Accounts::InboxesController
  extend ActiveSupport::Concern

  def wavoip_sdk_bootstrap
    authorize @inbox, :show?
    channel = @inbox.channel
    return head :not_found unless channel.is_a?(Channel::Wavoip)

    render json: { device_token: channel.device_token }
  end

  def regenerate_wavoip_webhook_key
    authorize @inbox, :regenerate_wavoip_webhook_key?
    channel = @inbox.channel
    return head :not_found unless channel.is_a?(Channel::Wavoip)

    channel.regenerate_webhook_key!
    @inbox.update_account_cache
    render json: { wavoip_webhook_url: channel.webhook_url }
  end

  def evolution_connection
    authorize @inbox, :show?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    payload = Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).connection_payload
    render json: payload
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def evolution_reconnect
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).reconnect!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def evolution_logout
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).logout!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def evolution_restart
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel).restart!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def evolution_import
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ImportJob.perform_later(channel.id, force: true)
    render json: import_payload_for(channel.reload)
  end

  private

  def evolution_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
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

  def create
    return super unless evolution_whatsapp_channel?

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
      render json: { message: error.message }, status: :unprocessable_entity
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
    evolution_params = params.require(:channel).permit(
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

    Custom::Whatsapp::Evolution::ProviderConfig.build(
      'base_url' => evolution_params[:base_url].to_s.strip.delete_suffix('/'),
      'instance_name' => evolution_params[:instance_name].to_s.strip,
      'api_key' => evolution_params[:api_key].to_s.strip
    ).merge((evolution_params[:provider_config] || {}).stringify_keys)
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
      provider_config: [:inbound_calls_enabled]
    )

    Current.account.wavoip_channels.create!(wavoip_params)
  end
end
