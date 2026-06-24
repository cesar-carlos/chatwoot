# frozen_string_literal: true

class Wavoip::ProcessWebhookJob < ApplicationJob
  queue_as :low

  def perform(inbox_id, payload)
    inbox = Inbox.find_by(id: inbox_id)
    if inbox.blank?
      Rails.logger.warn("[WAVOIP] Dropping webhook: inbox_id=#{inbox_id} not found")
      return
    end

    normalized = payload.with_indifferent_access
    result = Wavoip::Webhooks::Dispatcher.new(inbox: inbox, payload: payload).dispatch
    Rails.logger.info(
      "[WAVOIP] processed inbox_id=#{inbox.id} type=#{normalized[:type]} " \
      "action=#{normalized[:action]} call_id=#{webhook_call_id(normalized)} " \
      "status=#{normalized[:status]} outcome=#{outcome_for(result)}"
    )
  end

  private

  def webhook_call_id(payload)
    payload[:id].presence || payload[:whatsapp_call_id]
  end

  def outcome_for(result)
    return 'skipped' if result.nil?
    return 'upserted' if result.is_a?(Call)

    'processed'
  end
end
