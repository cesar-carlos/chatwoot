# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ApiError < StandardError
  attr_reader :status, :body, :base_message

  def initialize(message = nil, status: nil, body: nil)
    @status = status
    @body = body
    @base_message = message
    super(log_message)
  end

  def log_message
    self.class.compose_message(base_message, status, body)
  end

  def user_message
    return log_message unless Rails.env.production?

    detail = self.class.safe_response_detail(body, status)
    return "#{base_message}: #{detail}" if base_message.present? && detail.present?

    base_message.presence || detail.presence || 'Evolution Go API request failed'
  end

  def self.safe_response_detail(body, status)
    case status.to_i
    when 401
      response_detail(body, status)
    when 403
      sanitize_detail(extract_message(body)) ||
        'Evolution Go rejected the request (check global vs instance API key)'
    when 400, 404, 422
      sanitize_detail(extract_message(body))
    else
      text = extract_message(body)
      return 'An Evolution Go instance with this name already exists' if duplicate_instance?(text)
      return sanitize_detail(text) if session_disconnected?(text)

      nil
    end
  end

  def self.compose_message(message, status, body)
    detail = response_detail(body, status)
    return message if detail.blank?

    "#{message}: #{detail}"
  end

  def self.response_detail(body, status)
    case status.to_i
    when 401
      return 'Evolution Go rejected the API key (check global_api_key or instance_token)'
    when 403
      return sanitize_detail(extract_message(body)) ||
             'Evolution Go rejected the request (check global vs instance API key)'
    end

    text = extract_message(body)
    return 'An Evolution Go instance with this name already exists' if duplicate_instance?(text)
    return friendly_session_message if session_disconnected?(text)

    sanitize_detail(text)
  end

  def self.extract_message(body)
    return body.to_s unless body.is_a?(Hash)

    error = body['error']
    message = body['message']
    message ||= error.is_a?(Hash) ? error['message'] : error
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
    text.to_s.match?(/already (exists|in use)/i)
  end

  def self.session_disconnected?(text)
    text.to_s.match?(/client is nil|not connected|logged.?out|session.*disconnected/i)
  end

  def self.friendly_session_message
    'WhatsApp session disconnected — reconnect the inbox'
  end

  def self.sanitize_detail(text)
    return nil if text.blank?
    return friendly_session_message if session_disconnected?(text)

    text.to_s.truncate(200)
  end
end
