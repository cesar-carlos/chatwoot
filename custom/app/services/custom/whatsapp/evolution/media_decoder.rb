# frozen_string_literal: true

module Custom::Whatsapp::Evolution::MediaDecoder
  MAX_DECODE_BYTES = 25.megabytes

  module_function

  def decode!(base64, max_bytes: MAX_DECODE_BYTES)
    return nil if base64.blank?

    raise ArgumentError, "Evolution media exceeds #{max_bytes} byte limit" if estimated_decoded_size(base64) > max_bytes

    data = Base64.decode64(base64)
    raise ArgumentError, "Evolution media exceeds #{max_bytes} byte limit" if data.bytesize > max_bytes

    data
  end

  def estimated_decoded_size(base64)
    (base64.to_s.length * 3) / 4
  end
end
