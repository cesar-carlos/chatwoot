# frozen_string_literal: true

# Daily soft alert: voice-enabled Wavoip channels that previously received
# webhooks but have been quiet for 24h+. Blank last_webhook_at is skipped
# (setup verified, no traffic yet — checklist handles that separately).
class Wavoip::WebhookStaleAlertJob < ApplicationJob
  queue_as :default

  STALE_AFTER = 24.hours

  def perform
    Channel::Wavoip.find_each do |channel|
      next unless channel.voice_enabled?
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
    return false if raw.blank?

    Time.zone.parse(raw.to_s) < STALE_AFTER.ago
  rescue ArgumentError, TypeError
    false
  end
end
