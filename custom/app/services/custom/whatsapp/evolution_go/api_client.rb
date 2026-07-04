# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::ApiClient
  REQUEST_TIMEOUT = 30
  OPEN_TIMEOUT = 10
  MAX_RETRIES = 1
  RETRY_BACKOFF = 0.3
  RETRYABLE_STATUSES = (500..599)
  NETWORK_ERRORS = [
    HTTParty::Error,
    SocketError,
    EOFError,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Timeout::Error
  ].freeze

  def self.for_channel(channel)
    config = channel.provider_config || {}
    new(
      base_url: config['base_url'],
      global_api_key: config['global_api_key'],
      instance_token: config['instance_token'],
      instance_name: config['instance_name']
    )
  end

  def self.raise_unless_success!(response, message)
    return if response.success?

    raise Custom::Whatsapp::EvolutionGo::ApiError.new(
      message,
      status: response.code,
      body: response.parsed_response
    )
  end

  def initialize(base_url:, global_api_key: nil, instance_token: nil, instance_name: nil)
    @base_url = base_url.to_s.strip.delete_suffix('/')
    @global_api_key = global_api_key.to_s.strip
    @instance_token = instance_token.to_s.strip
    @instance_name = instance_name.to_s.strip
  end

  def server_ok
    get('/server/ok')
  end

  def create_instance(name:, token: nil, proxy: nil)
    body = { name: name }
    body[:token] = token if token.present?
    body[:proxy] = proxy if proxy.present?
    post('/instance/create', body, headers: admin_headers)
  end

  def connect(webhook_url:, subscribe:, **opts)
    body = { webhookUrl: webhook_url, subscribe: subscribe }.merge(opts.compact)
    post('/instance/connect', body, headers: instance_headers)
  end

  def disconnect
    post('/instance/disconnect', {}, headers: instance_headers)
  end

  def logout
    delete('/instance/logout', headers: instance_headers)
  end

  def qr_code
    get('/instance/qr', headers: instance_headers)
  end

  def connection_status
    get('/instance/status', headers: instance_headers)
  end

  def send_text(number:, text:, quoted: nil, delay: nil)
    body = { number: normalize_number(number), text: text }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?
    post('/send/text', body, headers: instance_headers)
  end

  def send_media(number:, type:, url:, caption: nil, filename: nil, quoted: nil, delay: nil)
    body = {
      number: normalize_number(number),
      type: type,
      url: url
    }
    body[:caption] = caption if caption.present?
    body[:filename] = filename if filename.present?
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?
    post('/send/media', body, headers: instance_headers)
  end

  def mark_messages_read(number:, ids:)
    post(
      '/message/markread',
      { number: normalize_number(number), id: Array.wrap(ids).map(&:to_s) },
      headers: instance_headers
    )
  end

  def download_media(message_envelope)
    envelope = message_envelope.with_indifferent_access
    response = post('/message/downloadimage', download_image_body(envelope), headers: instance_headers)
    return response if response.success?

    message = envelope[:message] || envelope['message']
    post('/message/downloadmedia', { message: message }, headers: instance_headers)
  end

  def advanced_settings(instance_id)
    get("/instance/#{instance_id}/advanced-settings", headers: instance_headers)
  end

  def update_advanced_settings(instance_id, settings:)
    put("/instance/#{instance_id}/advanced-settings", settings, headers: instance_headers)
  end

  def delete_proxy(instance_id)
    delete("/instance/proxy/#{instance_id}", headers: admin_headers)
  end

  def delete_instance(instance_id)
    delete("/instance/delete/#{instance_id}", headers: admin_headers)
  end

  def unwrap(response)
    parsed = response.parsed_response
    return {} unless parsed.is_a?(Hash)

    parsed['data'] || {}
  end

  def dig_field(hash, *keys)
    Custom::Whatsapp::EvolutionGo::FieldDig.dig_field(hash, *keys)
  end

  private

  def admin_headers
    { 'apikey' => @global_api_key, 'Content-Type' => 'application/json' }
  end

  def instance_headers
    { 'apikey' => @instance_token, 'Content-Type' => 'application/json' }
  end

  def get(path, headers:)
    request(:get, path, nil, headers: headers)
  end

  def post(path, body, headers:)
    request(:post, path, body, headers: headers)
  end

  def put(path, body, headers:)
    request(:put, path, body, headers: headers)
  end

  def delete(path, headers:)
    request(:delete, path, nil, headers: headers)
  end

  def download_image_body(envelope)
    key = envelope[:key] || envelope['key'] || {}
    message = envelope[:message] || envelope['message'] || {}

    {
      id: key[:id] || key['id'],
      remoteJid: key[:remoteJid] || key['remoteJid'],
      message: message
    }.compact
  end

  def request(method, path, body, headers:, attempt: 0)
    options = { headers: headers, timeout: REQUEST_TIMEOUT, open_timeout: OPEN_TIMEOUT }
    options[:body] = body.to_json if body.present?

    response = HTTParty.public_send(method, "#{@base_url}#{path}", options)
    if !response.success? && attempt < MAX_RETRIES && retryable_failure?(response)
      return retry_request(method, path, body, headers, attempt)
    end

    ensure_parseable_response!(response, method, path)
    response
  rescue *NETWORK_ERRORS => e
    return retry_request(method, path, body, headers, attempt) if attempt < MAX_RETRIES

    raise Custom::Whatsapp::EvolutionGo::ApiError.new(
      "Evolution Go API request failed: #{method.to_s.upcase} #{path}",
      body: e.message
    )
  end

  def retry_request(method, path, body, headers, attempt)
    sleep(RETRY_BACKOFF * (attempt + 1))
    request(method, path, body, headers: headers, attempt: attempt + 1)
  end

  def retryable_failure?(response)
    RETRYABLE_STATUSES.cover?(response.code.to_i)
  end

  def ensure_parseable_response!(response, method, path)
    return if response.body.blank?

    response.parsed_response
  rescue JSON::ParserError
    raise Custom::Whatsapp::EvolutionGo::ApiError.new(
      "Evolution Go API returned non-JSON: #{method.to_s.upcase} #{path}",
      status: response.code,
      body: response.body.to_s.truncate(500)
    )
  end

  def normalize_number(number)
    number.to_s.gsub(/\D/, '')
  end
end
