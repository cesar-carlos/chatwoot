# frozen_string_literal: true

class Webhooks::EvolutionController < ActionController::API
  before_action :authenticate_webhook!

  def process_payload
    Webhooks::WhatsappEventsJob.perform_later(
      sanitized_job_payload.merge(instance_name: params[:instance_name])
    )
    head :ok
  end

  private

  def authenticate_webhook!
    @channel = find_channel_by_instance_name
    return head :not_found if @channel.blank?

    return if webhook_token_valid?
    return if apikey_valid?

    head :unauthorized
    nil
  end

  def webhook_token_valid?
    stored_token = @channel.provider_config['webhook_token'].to_s.strip
    return false if stored_token.blank?

    query_token = params[:token].to_s.strip
    query_token.present? && ActiveSupport::SecurityUtils.secure_compare(query_token, stored_token)
  end

  def apikey_valid?
    envelope_key = (webhook_payload['apikey'].presence || request.headers['apikey']).to_s.strip
    stored_key = @channel.provider_config['api_key'].to_s.strip
    envelope_key.present? && stored_key.present? &&
      ActiveSupport::SecurityUtils.secure_compare(envelope_key, stored_key)
  end

  def find_channel_by_instance_name
    Channel::Whatsapp.where(provider: 'evolution')
                     .where("provider_config->>'instance_name' = ?", params[:instance_name])
                     .first
  end

  def webhook_payload
    params.to_unsafe_hash.except('controller', 'action', 'instance_name')
  end

  def sanitized_job_payload
    payload = webhook_payload.except('apikey', 'api_key', :apikey, :api_key)
    payload['event'] = Custom::Whatsapp::Evolution::EventNames.normalize(payload['event']) if payload['event'].present?
    payload
  end
end
