# frozen_string_literal: true

class Wavoip::ProcessWebhookJob < ApplicationJob
  queue_as :low

  def perform(inbox_id, payload)
    inbox = Inbox.find_by(id: inbox_id)
    if inbox.blank?
      Rails.logger.warn("[WAVOIP] Dropping webhook: inbox_id=#{inbox_id} not found")
      return
    end

    event_type = payload['type'].presence || payload[:type]
    Rails.logger.info("[WAVOIP] processed inbox_id=#{inbox.id} event_type=#{event_type}")
    Wavoip::Webhooks::Dispatcher.new(inbox: inbox, payload: payload).dispatch
  end
end
