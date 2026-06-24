# frozen_string_literal: true

class Wavoip::DeviceStatusService
  class ApiError < StandardError; end

  CONNECTION_STATE_CACHE_TTL = 15.seconds
  DEVICES_BASE_URL = 'https://devices.wavoip.com'

  pattr_initialize [:channel!]

  def connection_payload(force: false)
    live = refresh_device_status!(force: force)
    channel.reload
    config = channel.provider_config || {}

    {
      device_status: config['device_status'],
      phone_number: channel.phone_number,
      live: live.present?,
      contact_phone: live&.dig('contact', 'phone')
    }
  end

  def logout!
    token = channel.device_token
    raise ApiError, 'Device token missing' if token.blank?

    response = HTTParty.get(
      "#{device_base_url(token)}/whatsapp/logout",
      timeout: 15
    )
    raise ApiError, 'Wavoip logout failed' unless response.success?

    persist_status!({ 'status' => 'close' })
    invalidate_cache!
  end

  def refresh_device_status!(force: false)
    cache_key = cache_key_for_channel
    return if !force && Rails.cache.read(cache_key)

    result = fetch_all_info
    if result
      persist_status!(result)
      Rails.cache.write(cache_key, true, expires_in: CONNECTION_STATE_CACHE_TTL)
    end
    result
  end

  private

  def fetch_all_info
    token = channel.device_token
    return nil if token.blank?

    response = HTTParty.get(
      "#{device_base_url(token)}/whatsapp/all_info",
      timeout: 10
    )
    return nil unless response.success?

    response.parsed_response['result']
  rescue StandardError => e
    Rails.logger.warn "[WAVOIP] all_info failed channel=#{channel.id}: #{e.class} #{e.message}"
    nil
  end

  def persist_status!(result)
    status = result['status'].presence
    return if status.blank?

    config = (channel.provider_config || {}).dup
    config['device_status'] = status
    channel.update!(provider_config: config)

    contact_phone = result.dig('contact', 'phone').presence
    channel.update!(phone_number: contact_phone) if contact_phone.present?
  end

  def device_base_url(token)
    "#{DEVICES_BASE_URL}/#{token}"
  end

  def cache_key_for_channel
    "wavoip:device_status:#{channel.id}"
  end

  def invalidate_cache!
    Rails.cache.delete(cache_key_for_channel)
  end
end
