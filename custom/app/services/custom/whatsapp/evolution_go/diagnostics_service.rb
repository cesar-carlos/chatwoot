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
      last_webhook_at: config['last_webhook_at']
    }
  end

  private

  def webhook_url
    Custom::Whatsapp::EvolutionGo::ConnectionProvisioner.webhook_url_for(channel)
  end
end
