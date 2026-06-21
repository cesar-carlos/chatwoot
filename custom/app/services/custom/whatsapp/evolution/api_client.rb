# frozen_string_literal: true

class Custom::Whatsapp::Evolution::ApiClient
  def initialize(base_url:, api_key:, instance_name:)
    @base_url = base_url.to_s.delete_suffix('/')
    @api_key = api_key
    @instance_name = instance_name
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

  def apply_webhook(url, events: ProviderConfig::WEBHOOK_EVENTS)
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

  def send_text(number:, text:, quoted: nil, delay: nil)
    body = { number: normalize_number(number), text: text }
    body[:quoted] = quoted if quoted.present?
    body[:delay] = delay if delay.present?

    response = post("/message/sendText/#{@instance_name}", body)
    return response if response.success?

    if response.code == 400
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

  def get_base64_from_media_message(message:, convert_to_mp4: false)
    body = { message: message }
    body[:convertToMp4] = true if convert_to_mp4

    post("/chat/getBase64FromMediaMessage/#{@instance_name}", body)
  end

  private

  def get(path)
    request(:get, path)
  end

  def post(path, body = nil)
    request(:post, path, body)
  end

  def delete(path)
    request(:delete, path)
  end

  def request(method, path, body = nil)
    options = {
      headers: {
        'apikey' => @api_key,
        'Content-Type' => 'application/json'
      }
    }
    options[:body] = body.to_json if body.present?

    HTTParty.public_send(method, "#{@base_url}#{path}", options)
  end

  def normalize_number(phone)
    phone.to_s.gsub(/\D/, '')
  end
end
