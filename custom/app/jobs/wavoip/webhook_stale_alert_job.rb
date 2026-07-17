# frozen_string_literal: true

# Daily soft alert: verified Wavoip channels with voice configured that have not
# received a webhook in 24h (or never recorded last_webhook_at).
class Wavoip::WebhookStaleAlertJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 24.hours

  def perform
    Channel::Wavoip.find_each do |channel|
      next unless channel.webhook_verified?
      next if channel.device_token.blank?
      next unless stale_webhook?(channel)

      Rails.logger.warn(
        "[WAVOIP] stale webhook channel_id=#{channel.id} inbox_id=#{channel.inbox&.id}"
      )
    end
  end

  private

  def stale_webhook?(channel)
    raw = channel.provider_config&.dig('last_webhook_at')
    return true if raw.blank?

    Time.zone.parse(raw.to_s) < STALE_AFTER.ago
  rescue ArgumentError, TypeError
    true
  end
end
