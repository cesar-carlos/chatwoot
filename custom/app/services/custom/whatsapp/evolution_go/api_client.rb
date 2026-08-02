# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength, Metrics/ParameterLists -- Evolution Go HTTP surface mirrors provider API
class Custom::Whatsapp::EvolutionGo::ApiClient
  REQUEST_TIMEOUT = 30
  # /user/avatar often hangs on WhatsApp CDN — fail fast so enrichment/refresh do not block workers.
  AVATAR_REQUEST_TIMEOUT = 12
  # /message/react can hang (~75s) on some Go versions — fail fast for dashboard UX.
  REACT_REQUEST_TIMEOUT = 15
  OPEN_TIMEOUT = 10
  MAX_RETRIES = 1
  RETRY_BACKOFF = 0.1
  RETRYABLE_STATUSES = (500..599)
  # /user/avatar can hang on WhatsApp CDN; retrying doubles the wait for bulk refresh.
  # /user/info: WhatsApp usync 429 arrives as HTTP 500 — retry worsens rate-overlimit.
  # /message/react: evolution-go#28 hang — do not retry.
  NON_RETRYABLE_PATHS = %w[/instance/create /user/avatar /user/info /message/react].freeze
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
    get('/server/ok', headers: {})
  end

  def create_instance(name:, token: nil, proxy: nil)
    body = { name: name, token: token.presence || SecureRandom.uuid }
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

  def pair(phone:, subscribe: nil)
    body = { phone: normalize_number(phone) }
    body[:subscribe] = Array.wrap(subscribe).presence if subscribe.present?
    post('/instance/pair', body, headers: instance_headers)
  end

  def connection_status
    get('/instance/status', headers: instance_headers)
  end

  def send_text(number:, text:, quoted: nil, delay: nil, format_jid: nil)
    body = { number: normalize_number(number), text: text }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?
    body[:formatJid] = format_jid unless format_jid.nil?
    post('/send/text', body, headers: instance_headers)
  end

  def send_media(number:, type:, url:, **options)
    body = {
      number: normalize_number(number),
      type: type,
      url: url
    }
    %i[caption filename quoted delay format_jid].each do |key|
      api_key = key == :format_jid ? :formatJid : key
      value = options[key]
      body[api_key] = value unless value.nil?
    end
    post('/send/media', body, headers: instance_headers)
  end

  def send_contact(number:, vcard:, quoted: nil, delay: nil, format_jid: nil)
    body = { number: normalize_number(number), vcard: vcard }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?
    body[:formatJid] = format_jid unless format_jid.nil?
    post('/send/contact', body, headers: instance_headers)
  end

  def send_sticker(number:, sticker:, quoted: nil, delay: nil, format_jid: nil)
    body = { number: normalize_number(number), sticker: sticker }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?
    body[:formatJid] = format_jid unless format_jid.nil?
    post('/send/sticker', body, headers: instance_headers)
  end

  def send_location(number:, latitude:, longitude:, name: nil, address: nil, quoted: nil, delay: nil, format_jid: nil)
    body = {
      number: normalize_number(number),
      latitude: latitude,
      longitude: longitude
    }
    body[:name] = name if name.present?
    body[:address] = address if address.present?
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?
    body[:formatJid] = format_jid unless format_jid.nil?
    post('/send/location', body, headers: instance_headers)
  end

  def send_buttons(number:, title:, description:, footer:, buttons:, **options)
    body = {
      number: normalize_number(number),
      title: title,
      description: description,
      footer: footer,
      buttons: buttons
    }
    %i[quoted delay format_jid image_url video_url].each do |key|
      api_key = case key
                when :format_jid then :formatJid
                when :image_url then :imageUrl
                when :video_url then :videoUrl
                else key
                end
      value = options[key]
      body[api_key] = value unless value.nil?
    end
    post('/send/button', body, headers: instance_headers)
  end

  def send_list(number:, title:, description:, footer_text:, button_text:, sections:, **options)
    body = {
      number: normalize_number(number),
      title: title,
      description: description,
      footerText: footer_text,
      buttonText: button_text,
      sections: sections
    }
    %i[quoted delay format_jid].each do |key|
      api_key = key == :format_jid ? :formatJid : key
      value = options[key]
      body[api_key] = value unless value.nil?
    end
    post('/send/list', body, headers: instance_headers)
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
    message = envelope[:message] || envelope['message']
    post('/message/downloadmedia', { message: message }, headers: instance_headers)
  end

  def advanced_settings(instance_id)
    get("/instance/#{instance_id}/advanced-settings", headers: instance_headers)
  end

  def instance_info(instance_id)
    get("/instance/info/#{instance_id}", headers: admin_headers)
  end

  def instance_logs(instance_id, start_date: nil, end_date: nil, level: nil)
    query = { start_date: start_date, end_date: end_date, level: level }.compact
    path = "/instance/logs/#{instance_id}"
    path = "#{path}?#{URI.encode_www_form(query)}" if query.present?
    get(path, headers: admin_headers)
  end

  def set_presence(number:, state:, is_audio: false)
    post(
      '/message/presence',
      { number: normalize_number(number), state: state.to_s, isAudio: is_audio },
      headers: instance_headers
    )
  end

  def user_check(number:)
    numbers = Array.wrap(number).filter_map { |value| normalize_number(value) }
    post('/user/check', { number: numbers }, headers: instance_headers)
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

  def user_contacts
    get('/user/contacts', headers: instance_headers)
  end

  def user_info(numbers:)
    post('/user/info', { number: Array.wrap(numbers).map(&:to_s) }, headers: instance_headers)
  end

  def user_avatar(number:, preview: false)
    post(
      '/user/avatar',
      { number: normalize_number(number), preview: preview },
      headers: instance_headers
    )
  end

  def delete_message(chat:, message_id:)
    post(
      '/message/delete',
      { chat: chat.to_s, messageId: message_id.to_s },
      headers: instance_headers
    )
  end

  def react(number:, id:, reaction:, from_me: false, participant: nil)
    body = {
      number: normalize_number(number),
      id: id.to_s,
      reaction: reaction.to_s,
      fromMe: ActiveModel::Type::Boolean.new.cast(from_me)
    }
    body[:participant] = participant.to_s if participant.present?
    post('/message/react', body, headers: instance_headers)
  end

  def edit_message(chat:, message_id:, message:)
    post(
      '/message/edit',
      { chat: chat.to_s, messageId: message_id.to_s, message: message.to_s },
      headers: instance_headers
    )
  end

  def history_sync(chat:, count: nil, message_info: nil)
    post(
      '/chat/history-sync',
      {
        count: (count || 100).to_i,
        messageInfo: message_info || { chat: chat.to_s }
      },
      headers: instance_headers
    )
  end

  def group_info(group_jid:)
    post('/group/info', { groupJid: group_jid.to_s }, headers: instance_headers)
  end

  def unwrap(response, context: nil)
    parsed = response.parsed_response
    return {} unless parsed.is_a?(Hash)

    data = parsed['data']
    if data.blank?
      top_level = extract_top_level_fields(parsed)
      if top_level.present?
        Rails.logger.info("[EVOLUTION_GO] unwrap used top-level fields context=#{context}") if context.present?
        return top_level
      end

      log_empty_unwrap(context, parsed)
      return {}
    end

    return unwrap_qr_string(data, parsed) if data.is_a?(String)

    data.is_a?(Hash) ? data : {}
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

  # rubocop:disable Metrics/CyclomaticComplexity -- HTTP retry / network rescue paths
  def request(method, path, body, headers:, attempt: 0)
    options = {
      headers: headers,
      timeout: timeout_for(path),
      open_timeout: OPEN_TIMEOUT,
      follow_redirects: false
    }
    options[:body] = body.to_json if body.present?

    response = HTTParty.public_send(method, "#{@base_url}#{path}", options)
    return retry_request(method, path, body, headers, attempt) if !response.success? && attempt < MAX_RETRIES && retryable_failure?(response, path)

    ensure_parseable_response!(response, method, path)
    response
  rescue *NETWORK_ERRORS => e
    # Honor NON_RETRYABLE_PATHS for network timeouts too (avatar CDN hangs).
    return retry_request(method, path, body, headers, attempt) if attempt < MAX_RETRIES && NON_RETRYABLE_PATHS.exclude?(path)

    raise Custom::Whatsapp::EvolutionGo::ApiError.new(
      "Evolution Go API request failed: #{method.to_s.upcase} #{path}",
      body: e.message
    )
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def timeout_for(path)
    case path
    when '/user/avatar' then AVATAR_REQUEST_TIMEOUT
    when '/message/react' then REACT_REQUEST_TIMEOUT
    else REQUEST_TIMEOUT
    end
  end

  def retry_request(method, path, body, headers, attempt)
    sleep(RETRY_BACKOFF * (attempt + 1))
    request(method, path, body, headers: headers, attempt: attempt + 1)
  end

  def retryable_failure?(response, path)
    return false if NON_RETRYABLE_PATHS.include?(path)

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
    value = number.to_s.strip
    return value if value.include?('@')

    value.gsub(/\D/, '')
  end

  def extract_top_level_fields(parsed)
    fields = {}
    token = dig_field(parsed, 'token', 'Token')
    fields['token'] = token if token.present?
    id = dig_field(parsed, 'id', 'Id', 'ID')
    fields['id'] = id if id.present?
    qrcode = dig_field(parsed, 'qrcode', 'Qrcode')
    fields['qrcode'] = qrcode if qrcode.present?
    code = dig_field(parsed, 'code', 'Code')
    fields['code'] = code if code.present?
    fields.presence
  end

  def unwrap_qr_string(data, parsed)
    {
      'qrcode' => data,
      'code' => dig_field(parsed, 'code', 'Code')
    }.compact
  end

  def log_empty_unwrap(context, parsed)
    return if context.blank?

    Rails.logger.warn(
      "[EVOLUTION_GO] unwrap returned empty payload context=#{context} keys=#{parsed.keys.join(',')}"
    )
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/ParameterLists
