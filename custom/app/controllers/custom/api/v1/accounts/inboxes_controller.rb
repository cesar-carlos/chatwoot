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

  private

  def create_channel
    return create_wavoip_channel if permitted_params[:channel][:type] == 'wavoip'

    super
  end

  def allowed_channel_types
    super + ['wavoip']
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
