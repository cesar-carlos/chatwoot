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

  def qr_payload(refresh: false)
    token = channel.device_token
    raise ApiError, 'Device token missing' if token.blank?

    if refresh
      restart_device!
      info = fetch_all_info
      persist_status!(info) if info
    else
      # Non-refresh: use cached all_info only if cache is cold; otherwise read DB status
      info = refresh_device_status!(force: false)
    end

    build_qr_payload(info, token)
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

  def restart_device!
    token = channel.device_token
    response = HTTParty.get(
      "#{device_base_url(token)}/device/restart",
      timeout: 15
    )
    raise ApiError, 'Wavoip restart failed' unless response.success?

    invalidate_cache!
  end

  def fetch_qr_image_base64(token)
    response = HTTParty.get(
      "#{device_base_url(token)}/whatsapp/qr-image",
      timeout: 15
    )
    return nil unless response.success? && response.body.present?

    content_type = response.headers['content-type'].presence || 'image/png'
    "data:#{content_type};base64,#{Base64.strict_encode64(response.body)}"
  rescue StandardError => e
    Rails.logger.warn "[WAVOIP] qr-image failed channel=#{channel.id}: #{e.class} #{e.message}"
    nil
  end

  def extract_qr_string(info)
    return nil unless info.is_a?(Hash)

    info['qrCode'].presence || info['qr_code'].presence
  end

  def build_qr_payload(info, token)
    channel.reload
    config = channel.provider_config || {}
    status = config['device_status']
    payload = {
      device_status: status,
      phone_number: channel.phone_number,
      live: info.present?
    }

    return payload if status == 'open'

    attach_qr_to_payload!(payload, info, token)
  end

  def attach_qr_to_payload!(payload, info, token)
    qr_string = extract_qr_string(info)
    if qr_string.present?
      payload[:qr_code] = qr_string
      return payload
    end

    qrcode_base64 = fetch_qr_image_base64(token)
    payload[:qrcode_base64] = qrcode_base64 if qrcode_base64.present?
    payload[:live] = true if qrcode_base64.present?
    payload
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
