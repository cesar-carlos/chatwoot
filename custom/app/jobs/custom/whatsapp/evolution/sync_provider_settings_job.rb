# frozen_string_literal: true

class Custom::Whatsapp::Evolution::SyncProviderSettingsJob < ApplicationJob
  queue_as :default

  retry_on Custom::Whatsapp::Evolution::ApiError, wait: :polynomially_longer, attempts: 3

  def perform(channel_id, synced_settings: false, synced_proxy: false)
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'evolution')
    return if channel.blank?

    service = Custom::Whatsapp::Evolution::ConnectionService.new(channel: channel)
    service.sync_settings! if synced_settings
    service.sync_proxy! if synced_proxy
    channel.clear_settings_sync_error!
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] settings sync failed for channel #{channel_id}: #{e.message}"
    channel&.record_settings_sync_error!(e.message)
    raise
  end
end
