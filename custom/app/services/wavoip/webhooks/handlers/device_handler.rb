# frozen_string_literal: true

class Wavoip::Webhooks::Handlers::DeviceHandler < Wavoip::Webhooks::Handlers::BaseHandler
  def perform
    channel = inbox.channel
    return unless channel.is_a?(Channel::Wavoip)

    channel.with_lock do
      channel.reload
      config = (channel.provider_config || {}).dup
      config['device_status'] = event.external_status
      config['id_session'] = event.session_id if event.session_id.present?
      config['webhook_verified_at'] ||= Time.current.iso8601
      channel.update!(provider_config: config)
    end
  end
end
