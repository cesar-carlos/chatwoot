# frozen_string_literal: true

module Custom::Whatsapp::Evolution::MediaDecoder
  MAX_DECODE_BYTES = 25.megabytes
  # Evolution Go `/message/downloadmedia` returns a full data URL in `data.base64`
  # (e.g. `data:application/pdf;base64,JVBERi0...`). Decoding the prefix as
  # base64 produces corrupt blobs (magic `75ab5a6a...`) that PDF/image viewers reject.
  DATA_URL_PATTERN = %r{\Adata:([^;,]+)?(?:;[^,]*)*;base64,}i

  module_function

  def decode!(base64, max_bytes: MAX_DECODE_BYTES)
    return nil if base64.blank?

    payload = strip_data_url_prefix(base64.to_s)
    raise ArgumentError, "Evolution media exceeds #{max_bytes} byte limit" if estimated_decoded_size(payload) > max_bytes

    data = Base64.decode64(payload)
    raise ArgumentError, "Evolution media exceeds #{max_bytes} byte limit" if data.bytesize > max_bytes

    data
  end

  def mime_type_from_data_url(value)
    match = DATA_URL_PATTERN.match(value.to_s)
    match&.[](1).presence
  end

  def strip_data_url_prefix(value)
    value.sub(DATA_URL_PATTERN, '')
  end

  def estimated_decoded_size(base64)
    (base64.to_s.length * 3) / 4
  end
end
