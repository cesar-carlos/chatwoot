# frozen_string_literal: true

class Custom::Whatsapp::EvolutionGo::WebhookSubscribeSync
  pattr_initialize [:channel!, :connection_service!]

  def self.canonical_events(config)
    config = (config || {}).stringify_keys
    events = Custom::Whatsapp::EvolutionGo::ProviderConfig::WEBHOOK_EVENTS.dup
    events << 'GROUP' unless ignore_groups?(config)
    events.freeze
  end

  def self.ignore_groups?(config)
    ActiveModel::Type::Boolean.new.cast((config || {})['ignore_groups'])
  end

  def canonical_events
    self.class.canonical_events(provider_config)
  end

  def merge_stored!
    stored = Array.wrap(provider_config['webhook_subscribe']).map { |event| event.to_s.upcase }.grep(/\A[A-Z_]+\z/)
    (canonical_events + stored).uniq
  end

  def sync!
    validate_webhook_base_url!
    ensure_webhook_token!
    events = merge_stored!
    response = api_client.connect(
      webhook_url: webhook_url,
      subscribe: events
    )
    Custom::Whatsapp::EvolutionGo::ApiClient.raise_unless_success!(response, 'Failed to sync Evolution Go webhook subscription')

    attrs = { 'webhook_subscribe' => events }
    attrs['connection_status'] = 'connecting' unless provider_config['connection_status'] == 'open'
    connection_service.persist_provider_config!(provider_config.merge(attrs))
    events
  end

  private

  def api_client
    @api_client ||= Custom::Whatsapp::EvolutionGo::ApiClient.for_channel(channel)
  end

  def provider_config
    channel.provider_config || {}
  end

  def webhook_url
    Custom::Whatsapp::EvolutionGo::ConnectionProvisioner.webhook_url_for(channel)
  end

  def validate_webhook_base_url!
    return if ENV.fetch('FRONTEND_URL', nil).present?

    raise Custom::Whatsapp::EvolutionGo::ApiError,
          'FRONTEND_URL is not configured; cannot register Evolution Go webhook'
  end

  def ensure_webhook_token!
    return if provider_config['webhook_token'].present?

    connection_service.update_runtime_config!('webhook_token' => SecureRandom.hex(16))
  end
end
