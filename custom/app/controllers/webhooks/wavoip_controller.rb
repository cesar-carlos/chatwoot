# frozen_string_literal: true

class Webhooks::WavoipController < ActionController::API
  def process_payload
    channel = Channel::Wavoip.find_by(webhook_key: params[:webhook_key])
    return head :unauthorized if channel.blank?

    inbox = channel.inbox
    return head :unauthorized if inbox.blank?

    Rails.logger.info(
      "[WAVOIP] webhook accepted inbox_id=#{inbox.id} event_type=#{webhook_payload['type']}"
    )

    Wavoip::ProcessWebhookJob.perform_later(inbox.id, webhook_payload)
    head :accepted
  end

  private

  def webhook_payload
    params.to_unsafe_hash.except('controller', 'action', 'webhook_key')
  end
end
