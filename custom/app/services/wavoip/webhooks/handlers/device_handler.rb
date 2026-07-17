# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::DeviceHandler < Wavoip::Webhooks::Handlers::BaseHandler
  # Wavoip sometimes sends human aliases; persist the canonical statuses used elsewhere.
  STATUS_ALIASES = {
    'connected' => 'open',
    'disconnected' => 'close'
  }.freeze

  def perform
    channel = inbox.channel
    return unless channel.is_a?(Channel::Wavoip)

    channel.with_lock do
      channel.reload
      config = (channel.provider_config || {}).dup
      config['device_status'] = normalized_device_status
      config['id_session'] = event.session_id if event.session_id.present?
      config['webhook_verified_at'] ||= Time.current.iso8601
      channel.update!(provider_config: config)
    end
  end

  private

  def normalized_device_status
    STATUS_ALIASES.fetch(event.external_status, event.external_status)
  end
end
