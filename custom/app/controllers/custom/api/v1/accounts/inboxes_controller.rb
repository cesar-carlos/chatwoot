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

    payload = Custom::Whatsapp::Evolution::ConnectionService.new(channel).connection_payload
    render json: payload
  end

  def evolution_reconnect
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel).reconnect!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def evolution_logout
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel).logout!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def evolution_restart
    authorize @inbox, :update?
    channel = @inbox.channel
    return head :not_found unless evolution_channel?(channel)

    Custom::Whatsapp::Evolution::ConnectionService.new(channel).restart!
    render json: connection_payload_for(channel)
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def evolution_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'evolution'
  end

  def connection_payload_for(channel)
    Custom::Whatsapp::Evolution::ConnectionService.new(channel).connection_payload
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
  rescue Custom::Whatsapp::Evolution::ApiError => e
    render json: { message: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "[EVOLUTION] inbox create failed: #{e.class} #{e.message}"
    render json: { message: 'Failed to provision Evolution instance' }, status: :unprocessable_entity
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
    permitted_params[:channel][:type] == 'whatsapp' &&
      permitted_params[:channel][:provider] == 'evolution'
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
      'base_url' => evolution_params[:base_url].to_s.delete_suffix('/'),
      'instance_name' => evolution_params[:instance_name],
      'api_key' => evolution_params[:api_key]
    ).merge((evolution_params[:provider_config] || {}).stringify_keys)
  end

  def provision_evolution_channel!(channel)
    Custom::Whatsapp::Evolution::ConnectionService.new(channel).provision_new_instance!
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
