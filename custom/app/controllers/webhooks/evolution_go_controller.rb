# frozen_string_literal: true

class Webhooks::EvolutionGoController < ActionController::API
  # Avoids a synchronous DB write on every webhook when a burst arrives, while
  # still keeping `last_webhook_at` accurate to within TOUCH_DEBOUNCE_SECONDS.
  TOUCH_DEBOUNCE_SECONDS = 30

  before_action :authenticate_webhook!

  def process_payload
    touch_last_webhook_at!

    Webhooks::WhatsappEventsJob.set(queue: :default).perform_later(
      sanitized_job_payload.merge(
        evolution_go_instance_name: params[:instance_name],
        channel_id: @channel.id
      )
    )
    head :ok
  end

  private

  def authenticate_webhook!
    @channel = find_channel_by_instance_name
    return head :not_found if @channel.blank?
    return head :unauthorized unless webhook_token_valid?

    nil
  end

  def webhook_token_valid?
    stored_token = @channel.provider_config['webhook_token'].to_s.strip
    return false if stored_token.blank?

    query_token = params[:token].to_s.strip
    bearer = request.headers['Authorization'].to_s.remove(/^Bearer /i).strip
    provided = query_token.presence || bearer
    provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, stored_token)
  end

  def find_channel_by_instance_name
    Channel::Whatsapp.where(provider: 'evolution_go')
                     .where("provider_config->>'instance_name' = ?", params[:instance_name])
                     .first
  end

  def sanitized_job_payload
    payload = params.to_unsafe_hash.except('controller', 'action', 'instance_name', 'token')
    payload.delete('instance')
    payload
  end

  def touch_last_webhook_at!
    debounced = Redis::Alfred.set(touch_debounce_key, true, nx: true, ex: TOUCH_DEBOUNCE_SECONDS)
    return unless debounced

    config = (@channel.provider_config || {}).stringify_keys.merge(
      'last_webhook_at' => Time.current.utc.iso8601(3)
    )
    Custom::Whatsapp::EvolutionGo::ProviderConfigMerger.merge!(@channel, config.slice('last_webhook_at'))
  end

  def touch_debounce_key
    format(Redis::RedisKeys::EVOLUTION_GO_WEBHOOK_TOUCH_DEBOUNCE, channel_id: @channel.id)
  end
end
