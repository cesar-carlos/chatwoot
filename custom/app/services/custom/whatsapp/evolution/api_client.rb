# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength -- Evolution HTTP surface grows with provider features
class Custom::Whatsapp::Evolution::ApiClient
  REQUEST_TIMEOUT = 30
  OPEN_TIMEOUT = 10
  TEXT_BODY_VALIDATION_PATTERN = /text(?:message)?/i

  def self.for_channel(channel)
    config = channel.provider_config || {}
    new(
      base_url: config['base_url'],
      api_key: config['api_key'],
      instance_name: config['instance_name']
    )
  end

  def self.raise_unless_success!(response, message)
    return if response.success?

    raise Custom::Whatsapp::Evolution::ApiError.new(
      message,
      status: response.code,
      body: response.parsed_response
    )
  end

  def initialize(base_url:, api_key:, instance_name:)
    @base_url = base_url.to_s.strip.delete_suffix('/')
    @api_key = api_key.to_s.strip
    @instance_name = instance_name.to_s.strip
  end

  def create_instance(body)
    post('/instance/create', body)
  end

  def connect(number: nil)
    query = number.present? ? "?number=#{CGI.escape(number.to_s)}" : ''
    get("/instance/connect/#{@instance_name}#{query}")
  end

  def connection_state
    get("/instance/connectionState/#{@instance_name}")
  end

  def logout_instance
    delete("/instance/logout/#{@instance_name}")
  end

  def restart_instance
    post("/instance/restart/#{@instance_name}", {})
  end

  def delete_instance
    delete("/instance/delete/#{@instance_name}")
  end

  def apply_webhook(url, events: Custom::Whatsapp::Evolution::ProviderConfig::WEBHOOK_EVENTS)
    post("/webhook/set/#{@instance_name}", {
           webhook: {
             enabled: true,
             url: url,
             byEvents: false,
             base64: false,
             events: events
           }
         })
  end

  def apply_settings(settings)
    post("/settings/set/#{@instance_name}", settings)
  end

  def apply_proxy(proxy)
    post("/proxy/set/#{@instance_name}", proxy)
  end

  def disable_chatwoot_integration
    # Evolution v2.3.x schema requires all fields even when enabled: false
    post("/chatwoot/set/#{@instance_name}", {
           enabled: false,
           accountId: '0',
           token: 'disabled',
           url: 'http://localhost',
           signMsg: false,
           reopenConversation: false,
           conversationPending: false
         })
  end

  def find_chatwoot_integration
    get("/chatwoot/find/#{@instance_name}")
  end

  def send_text(number:, text:, quoted: nil, delay: nil)
    body = { number: normalize_number(number), text: text }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?

    response = post("/message/sendText/#{@instance_name}", body)
    return response if response.success?

    if response.code == 400 && text_body_validation_error?(response)
      fallback = body.except(:text).merge(textMessage: { text: text })
      response = post("/message/sendText/#{@instance_name}", fallback)
    end

    response
  end

  def send_media(number:, mediatype:, media:, **options)
    body = {
      number: normalize_number(number),
      mediatype: mediatype,
      media: media
    }
    body[:caption] = options[:caption] if options[:caption].present?
    body[:fileName] = options[:file_name] if options[:file_name].present?
    body[:quoted] = options[:quoted] if options[:quoted].present?
    body[:delay] = options[:delay] if options[:delay].present?

    post("/message/sendMedia/#{@instance_name}", body)
  end

  def send_audio(number:, audio:, quoted: nil, delay: nil)
    body = { number: normalize_number(number), audio: audio }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?

    post("/message/sendWhatsAppAudio/#{@instance_name}", body)
  end

  def send_buttons(number:, title:, buttons:, **options)
    body = {
      number: normalize_number(number),
      title: title,
      buttons: buttons
    }
    body[:description] = options[:description] if options[:description].present?
    body[:footer] = options[:footer] if options[:footer].present?
    body[:quoted] = options[:quoted] if options[:quoted].present?
    body[:delay] = options[:delay] if options[:delay].present?

    post("/message/sendButtons/#{@instance_name}", body)
  end

  def send_list(number:, title:, button_text:, sections:, **options)
    body = {
      number: normalize_number(number),
      title: title,
      buttonText: button_text,
      sections: sections
    }
    body[:description] = options[:description] if options[:description].present?
    body[:footerText] = options[:footer_text] if options[:footer_text].present?
    body[:quoted] = options[:quoted] if options[:quoted].present?
    body[:delay] = options[:delay] if options[:delay].present?

    post("/message/sendList/#{@instance_name}", body)
  end

  def get_base64_from_media_message(message:, convert_to_mp4: false)
    body = { message: message }
    body[:convertToMp4] = true if convert_to_mp4

    post("/chat/getBase64FromMediaMessage/#{@instance_name}", body)
  end

  def mark_message_as_read(read_messages:)
    post("/chat/markMessageAsRead/#{@instance_name}", { readMessages: read_messages })
  end

  def delete_message_for_everyone(id:, remote_jid:, from_me:)
    delete(
      "/chat/deleteMessageForEveryone/#{@instance_name}",
      { id: id, fromMe: from_me, remoteJid: remote_jid }
    )
  end

  def find_contacts(page: 1, offset: 50, where: nil)
    body = { page: page, offset: offset }
    body[:where] = where if where.present?

    post("/chat/findContacts/#{@instance_name}", body)
  end

  def find_messages(page: 1, offset: 50, where: nil)
    body = { page: page, offset: offset }
    body[:where] = where if where.present?

    post("/chat/findMessages/#{@instance_name}", body)
  end

  def find_chats(page: 1, offset: 50, where: nil)
    body = { page: page, offset: offset }
    body[:where] = where if where.present?

    post("/chat/findChats/#{@instance_name}", body)
  end

  def fetch_profile_picture_url(number:)
    post("/chat/fetchProfilePictureUrl/#{@instance_name}", { number: profile_lookup_number(number) })
  end

  def fetch_profile(number:)
    post("/chat/fetchProfile/#{@instance_name}", { number: profile_lookup_number(number) })
  end

  def fetch_business_profile(number:)
    post("/chat/fetchBusinessProfile/#{@instance_name}", { number: profile_lookup_number(number) })
  end

  private

  def get(path)
    request(:get, path)
  end

  def post(path, body = nil)
    request(:post, path, body)
  end

  def delete(path, body = nil)
    request(:delete, path, body)
  end

  def request(method, path, body = nil)
    options = {
      headers: {
        'apikey' => @api_key,
        'Content-Type' => 'application/json'
      }
    }
    options[:body] = body.to_json if body.present?
    options[:timeout] = REQUEST_TIMEOUT
    options[:open_timeout] = OPEN_TIMEOUT

    HTTParty.public_send(method, "#{@base_url}#{path}", options)
  end

  def normalize_number(phone)
    phone.to_s.gsub(/\D/, '')
  end

  def profile_lookup_number(number)
    value = number.to_s.strip
    return value if value.include?('@')

    normalize_number(value)
  end

  def text_body_validation_error?(response)
    body = response.parsed_response
    message = if body.is_a?(Hash)
                body.dig('response', 'message') || body['message'] || body.dig('error', 'message') || body['error']
              else
                body.to_s
              end
    message.to_s.match?(TEXT_BODY_VALIDATION_PATTERN)
  end
end
# rubocop:enable Metrics/ClassLength
