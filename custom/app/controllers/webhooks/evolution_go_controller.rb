# frozen_string_literal: true

class Webhooks::EvolutionGoController < ActionController::API
  before_action :authenticate_webhook!

  def process_payload
    Webhooks::WhatsappEventsJob.perform_later(
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
end
