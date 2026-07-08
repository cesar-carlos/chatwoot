# frozen_string_literal: true

class Webhooks::WavoipController < ActionController::API
  MAX_PAYLOAD_BYTES = 64.kilobytes
  ALLOWED_PAYLOAD_KEYS = %w[
    type action status direction phone caller receiver whatsapp_call_id id duration
    id_session call_type record_status record_url peer
  ].freeze
  ALLOWED_PEER_KEYS = %w[phone display_name].freeze

  def process_payload
    return head :payload_too_large if payload_too_large?

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

  def payload_too_large?
    request.content_length.to_i > MAX_PAYLOAD_BYTES || request.raw_post.bytesize > MAX_PAYLOAD_BYTES
  end

  def webhook_payload
    raw = params.to_unsafe_hash.except('controller', 'action', 'webhook_key')
    filter_whitelisted(raw)
  end

  def filter_whitelisted(payload)
    filtered = payload.slice(*ALLOWED_PAYLOAD_KEYS)
    peer = filtered['peer']
    filtered['peer'] = peer.slice(*ALLOWED_PEER_KEYS) if peer.is_a?(Hash)
    filtered
  end
end
