# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ApiError < StandardError
  attr_reader :status, :body

  def initialize(message = nil, status: nil, body: nil)
    @status = status
    @body = body
    super(self.class.compose_message(message, status, body))
  end

  def self.compose_message(message, status, body)
    detail = response_detail(body, status)
    return message if detail.blank?

    "#{message}: #{detail}"
  end

  def self.response_detail(body, status)
    case status.to_i
    when 401
      return 'Evolution API rejected the API key (use the global AUTHENTICATION_API_KEY from your Evolution server)'
  end

    text = extract_message(body)
    return 'An Evolution instance with this name already exists' if duplicate_instance?(text)

    text
  end

  def self.extract_message(body)
    return body.to_s unless body.is_a?(Hash)

    message = body.dig('response', 'message') || body['message'] || body.dig('error', 'message') || body['error']
    normalize_message(message)
  end

  def self.normalize_message(message)
    case message
    when Array then message.compact_blank.join(', ')
    when Hash then message['message'] || message.to_s
    else message.to_s.presence
    end
  end

  def self.duplicate_instance?(text)
    text.to_s.match?(/already in use/i)
  end
end
