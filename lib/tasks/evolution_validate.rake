# frozen_string_literal: true

namespace :evolution do
  desc 'Smoke-test validation-checklist §2–4 against a real Evolution instance (set EVOLUTION_BASE_URL, EVOLUTION_API_KEY, EVOLUTION_INSTANCE, FRONTEND_URL, CHATWOOT_BASE_URL)'
  task validate_checklist: :environment do
    EvolutionValidateChecklist.new.run
  end
end

class EvolutionValidateChecklist
  def run
    base_url = ENV.fetch('EVOLUTION_BASE_URL', nil)&.delete_suffix('/')
    api_key = ENV.fetch('EVOLUTION_API_KEY', nil)
    instance = ENV.fetch('EVOLUTION_INSTANCE', nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)&.delete_suffix('/')
    chatwoot_base = ENV.fetch('CHATWOOT_BASE_URL', ENV.fetch('FRONTEND_URL', nil))&.delete_suffix('/')

    missing = %w[EVOLUTION_BASE_URL EVOLUTION_API_KEY EVOLUTION_INSTANCE FRONTEND_URL].select do |key|
      ENV[key].blank?
    end
    abort("Missing env: #{missing.join(', ')}") if missing.any?

    puts "== Evolution validation checklist (instance: #{instance}) =="

    state_response = evolution_get("#{base_url}/instance/connectionState/#{instance}", api_key)
    state = state_response.dig('instance', 'state') || state_response['state']
    puts "§4 connection_state: #{state || 'unknown'}"

    if state != 'open'
      connect_response = evolution_get("#{base_url}/instance/connect/#{instance}", api_key)
      has_qr = connect_response.dig('qrcode', 'base64').present? || connect_response['base64'].present?
      puts "§4 connect QR present: #{has_qr}"
      abort('§4 FAILED: no QR returned from connect — scan required before continuing') unless has_qr
    else
      puts '§4 connect QR: skipped (instance already open)'
    end

    webhook_url = "#{frontend_url}/webhooks/evolution/#{instance}"
    evolution_post(
      "#{base_url}/webhook/set/#{instance}",
      api_key,
      webhook: {
        enabled: true,
        url: webhook_url,
        byEvents: false,
        base64: false,
        events: %w[MESSAGES_UPSERT CONNECTION_UPDATE QRCODE_UPDATED]
      }
    )
    webhook_find = evolution_get("#{base_url}/webhook/find/#{instance}", api_key)
    registered_url = webhook_find.dig('webhook', 'url') || webhook_find['url']
    puts "§2 webhook URL: #{registered_url}"
    abort('§2 FAILED: webhook URL mismatch') unless registered_url.to_s.include?(instance)

    channel = Channel::Whatsapp.find_by(
      "provider = 'evolution' AND provider_config->>'instance_name' = ?",
      instance
    )
    if channel.blank?
      puts '§2 webhook POST: skipped (no matching Chatwoot channel — create inbox first)'
    else
      fixture = JSON.parse(Rails.root.join('spec/fixtures/evolution/messages_upsert_text.json').read)
      fixture['instance'] = instance
      fixture['apikey'] = channel.provider_config['api_key']
      uri = URI("#{chatwoot_base}/webhooks/evolution/#{instance}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['X-Forwarded-Proto'] = 'https' if uri.host.in?(%w[localhost 127.0.0.1])
      request.body = fixture.to_json
      response = http.request(request)
      puts "§2 Chatwoot webhook HTTP: #{response.code}"
      abort('§2 FAILED: webhook did not return 200') unless response.code.to_i == 200
    end

    test_phone = ENV.fetch('EVOLUTION_TEST_PHONE', nil)
    if test_phone.blank?
      puts '§3 sendText: skipped (set EVOLUTION_TEST_PHONE to validate outbound)'
    else
      instance_token = channel&.provider_config&.dig('api_key') || api_key
      send_response = evolution_post(
        "#{base_url}/message/sendText/#{instance}",
        instance_token,
        number: test_phone,
        text: "checklist ping #{Time.now.to_i}"
      )
      message_id = send_response.dig('key', 'id')
      puts "§3 sendText key.id: #{message_id}"
      abort('§3 FAILED: sendText response missing key.id') if message_id.blank?
    end

    puts '== Checklist smoke test completed =='
  end

  private

  def evolution_get(url, api_key)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    request = Net::HTTP::Get.new(uri)
    request['apikey'] = api_key
    JSON.parse(http.request(request).body)
  end

  def evolution_post(url, api_key, body)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    request = Net::HTTP::Post.new(uri)
    request['apikey'] = api_key
    request['Content-Type'] = 'application/json'
    request.body = body.to_json
    JSON.parse(http.request(request).body)
  end
end
