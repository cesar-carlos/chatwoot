# frozen_string_literal: true

class Custom::Notification::BrowserPushPayload
  # Leave room for the aes128gcm header, padding and authentication tag.
  MAX_JSON_BYTES = 3900
  MAX_TITLE_LENGTH = 120

  def self.generate(message)
    payload = message.with_indifferent_access
    payload[:title] = payload[:title].to_s.truncate(MAX_TITLE_LENGTH)
    json = JSON.generate(payload)
    return json if json.bytesize <= MAX_JSON_BYTES

    truncate_body(payload)
  end

  def self.truncate_body(payload)
    body = payload[:body].to_s
    payload[:body] = ''
    raise ArgumentError, 'Browser push metadata exceeds the payload limit' if JSON.generate(payload).bytesize > MAX_JSON_BYTES

    low = 0
    high = body.length
    while low < high
      length = (low + high + 1) / 2
      payload[:body] = "#{body[0, length]}…"
      if JSON.generate(payload).bytesize <= MAX_JSON_BYTES
        low = length
      else
        high = length - 1
      end
    end
    payload[:body] = low.positive? ? "#{body[0, low]}…" : ''
    JSON.generate(payload)
  end
  private_class_method :truncate_body
end
