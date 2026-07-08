# frozen_string_literal: true

require 'ipaddr'

module Custom::Whatsapp::Evolution::MediaPayload
  MAX_ENCODE_BYTES = Custom::Whatsapp::Evolution::MediaDecoder::MAX_DECODE_BYTES

  module_function

  def for_attachment(attachment)
    return attachment.download_url unless attachment.file.attached?

    url = attachment.download_url.presence
    return url if url.present? && publicly_accessible_url?(url)

    encode_attachment(attachment) || url
  end

  def publicly_accessible_url?(url)
    uri = URI.parse(url)
    return false unless uri.is_a?(URI::HTTP)

    host = uri.hostname.to_s.downcase
    return false if host.blank?
    return false if private_or_loopback_host?(host)
    return false if host.end_with?('.local', '.internal', '.localhost')

    true
  rescue URI::InvalidURIError
    false
  end

  def private_or_loopback_host?(host)
    ip = IPAddr.new(host)
    ip.loopback? || ip.private? || ip.link_local?
  rescue IPAddr::InvalidAddressError
    host == 'localhost' || host == '0.0.0.0'
  end

  def encode_attachment(attachment)
    content = attachment.file.blob.open(&:read)
    if content.bytesize > MAX_ENCODE_BYTES
      Rails.logger.warn("[EVOLUTION] attachment exceeds #{MAX_ENCODE_BYTES} bytes; skipping base64 encode")
      return nil
    end

    mime = attachment.file.content_type.presence || 'application/octet-stream'
    "data:#{mime};base64,#{Base64.strict_encode64(content)}"
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION] attachment base64 encode failed: #{e.message}")
    nil
  end
end
