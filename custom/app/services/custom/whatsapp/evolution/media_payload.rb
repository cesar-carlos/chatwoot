# frozen_string_literal: true

module Custom::Whatsapp::Evolution::MediaPayload
  PRIVATE_HOST_PATTERN = /
    \A
    (?:
      localhost |
      127\.0\.0\.1 |
      192\.168\. |
      10\. |
      172\.(?:1[6-9]|2\d|3[01])\.
    )
  /x

  module_function

  def for_attachment(attachment)
    return attachment.download_url unless attachment.file.attached?

    url = attachment.download_url.presence
    return url if url.present? && publicly_accessible_url?(url)

    encode_attachment(attachment) || url
  end

  def publicly_accessible_url?(url)
    uri = URI.parse(url)
    host = uri.host.to_s.downcase
    return false if host.blank?
    return false if PRIVATE_HOST_PATTERN.match?(host)

    true
  rescue URI::InvalidURIError
    false
  end

  def encode_attachment(attachment)
    content = attachment.file.blob.open(&:read)
    mime = attachment.file.content_type.presence || 'application/octet-stream'
    "data:#{mime};base64,#{Base64.strict_encode64(content)}"
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION] attachment base64 encode failed: #{e.message}")
    nil
  end
end
