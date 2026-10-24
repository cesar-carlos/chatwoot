# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::DiagnosticsService
  pattr_initialize [:channel!]

  def perform
    config = channel.provider_config || {}
    {
      webhook_url: webhook_url,
      connection_status: config['connection_status'],
      import_status: config['import_status'],
      import_error: config['import_error'],
      import_stats: config['import_stats'] || {},
      mutation_stats: config['mutation_stats'] || {},
      settings_sync_error: config['settings_sync_error'],
      webhook_subscribe: config['webhook_subscribe'],
      last_webhook_at: config['last_webhook_at'],
      contacts_refresh: Custom::Whatsapp::EvolutionGo::ContactsRefreshService.lock_status(channel),
      instance_info: instance_info_payload,
      instance_logs: instance_logs_payload
    }
  end

  private

  def webhook_url
    Custom::Whatsapp::EvolutionGo::ConnectionProvisioner.webhook_url_for(channel)
  end

  def instance_info_payload
    instance_id = (channel.provider_config || {})['instance_id']
    return if instance_id.blank?

    response = api_client.instance_info(instance_id)
    return unless response.success?

    redact_secrets(api_client.unwrap(response, context: 'instance_info'))
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] instance_info diagnostics failed channel=#{channel.id}: #{e.message}")
    nil
  end

  def instance_logs_payload
    instance_id = (channel.provider_config || {})['instance_id']
    return if instance_id.blank?

    response = api_client.instance_logs(instance_id)
    return unless response.success?

    parsed = response.parsed_response
    body = parsed.is_a?(Hash) ? (parsed['data'] || parsed) : parsed
    redact_secrets(body)
  rescue StandardError => e
    Rails.logger.warn("[EVOLUTION_GO] instance_logs diagnostics failed channel=#{channel.id}: #{e.message}")
    nil
  end

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def redact_secrets(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, item), redacted|
        next if key.to_s.match?(/token|apikey|api_key|password|secret/i)

        redacted[key] = redact_secrets(item)
      end
    when Array
      value.map { |item| redact_secrets(item) }
    when String
      value.gsub(/([?&]token=)[^&\s]+/i, '\1[redacted]')
    else
      value
    end
  end
end
