# frozen_string_literal: true

class Wavoip::ProcessWebhookJob < ApplicationJob
  queue_as :default

  before_enqueue do |job|
    payload = job.arguments[1]
    job.queue_name = self.class.queue_for_payload(payload).to_s
  end

  def self.queue_for_payload(payload)
    payload.with_indifferent_access[:type] == 'RECORD' ? :low : :default
  end

  def perform(inbox_id, payload)
    inbox = Inbox.find_by(id: inbox_id)
    if inbox.blank?
      Rails.logger.warn("[WAVOIP] Dropping webhook: inbox_id=#{inbox_id} not found")
      return
    end

    result = Wavoip::Webhooks::Dispatcher.new(inbox: inbox, payload: payload).dispatch
    log_payload = payload.with_indifferent_access
    Rails.logger.info(
      "[WAVOIP] processed inbox_id=#{inbox.id} type=#{log_payload[:type]} " \
      "action=#{log_payload[:action]} call_id=#{webhook_call_id(log_payload)} " \
      "status=#{log_payload[:status]} outcome=#{outcome_for(result)}"
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
