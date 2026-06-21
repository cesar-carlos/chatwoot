# frozen_string_literal: true

class Webhooks::EvolutionController < ActionController::API
  before_action :authenticate_webhook!

  def process_payload
    Webhooks::WhatsappEventsJob.perform_later(
      webhook_payload.merge(instance_name: params[:instance_name])
    )
    head :ok
  end

  private

  def authenticate_webhook!
    @channel = find_channel_by_instance_name
    return head :not_found if @channel.blank?

    envelope_key = (webhook_payload['apikey'].presence || request.headers['apikey']).to_s.strip
    stored_key = @channel.provider_config['api_key'].to_s.strip
    return if envelope_key.present? && stored_key.present? &&
              ActiveSupport::SecurityUtils.secure_compare(envelope_key, stored_key)

    head :unauthorized
    nil
  end

  def find_channel_by_instance_name
    Channel::Whatsapp.where(provider: 'evolution')
                     .where("provider_config->>'instance_name' = ?", params[:instance_name])
                     .first
  end

  def webhook_payload
    params.to_unsafe_hash.except('controller', 'action', 'instance_name')
  end
end
