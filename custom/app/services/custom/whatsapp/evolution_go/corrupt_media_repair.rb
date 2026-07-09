# frozen_string_literal: true

# Recovers Active Storage blobs that were saved by decoding Evolution Go
# data-URLs (`data:<mime>;base64,...`) without stripping the prefix.
# Re-encoding the corrupt bytes restores a filterable `data…base64…` string.
module Custom::Whatsapp::EvolutionGo::CorruptMediaRepair
  CORRUPT_DATA_URL_PATTERN = /\Adata(.+?)base64(.+)\z/m
  VALID_MAGIC = {
    'application/pdf' => ->(d) { d.start_with?('%PDF') },
    'image/jpeg' => ->(d) { d.byteslice(0, 2) == "\xFF\xD8".b },
    'image/jpg' => ->(d) { d.byteslice(0, 2) == "\xFF\xD8".b },
    'image/png' => ->(d) { d.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b },
    'image/webp' => ->(d) { d.byteslice(0, 4) == 'RIFF' },
    'audio/ogg' => ->(d) { d.byteslice(0, 4) == 'OggS' },
    'video/mp4' => ->(d) { d.include?('ftyp') }
  }.freeze

  module_function

  def corrupt_data_url_blob?(bytes)
    return false if bytes.blank?

    reencoded = [bytes].pack('m0')
    reencoded.match?(CORRUPT_DATA_URL_PATTERN)
  end

  def recover(bytes)
    reencoded = [bytes].pack('m0')
    match = CORRUPT_DATA_URL_PATTERN.match(reencoded)
    return if match.blank?

    mime = match[1].to_s
    payload = match[2].to_s
    recovered = Base64.decode64(payload)
    return if recovered.blank?

    { bytes: recovered, mime_type: mime.presence }
  end

  def valid_for_content_type?(bytes, content_type)
    checker = VALID_MAGIC[content_type.to_s]
    return true if checker.blank?

    checker.call(bytes)
  end
end
