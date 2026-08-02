# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength -- intentional Evolution Go provider overlay
module Custom::Channel::Whatsapp
  extend ActiveSupport::Concern

  MASKED_SECRET = '••••••••'

  # Secrets to mask in `dashboard_provider_config`, per gateway provider.
  # Add an entry here (and to `GATEWAY_PROVIDER_CONFIG_MODULES` below) when a
  # new provider is registered — no other method in this file needs to change.
  GATEWAY_SECRET_KEYS = {
    'evolution' => %w[api_key proxy_password webhook_token],
    'evolution_go' => %w[global_api_key instance_token proxy_password webhook_token]
  }.freeze

  prepended do
    after_commit :sync_gateway_templates_noop, on: :create, if: :gateway_provider?
    before_validation :sanitize_gateway_provider_config, on: :update, if: :gateway_provider?
    after_commit :sync_evolution_provider_to_api, on: :update, if: :evolution_provider?
    after_commit :sync_evolution_go_provider_to_api, on: :update, if: :evolution_go_provider?
    before_destroy :teardown_gateway_instance, if: :gateway_provider?
  end

  class_methods do
    # Every self-hosted WhatsApp gateway provider exposes the same
    # `ProviderConfig` interface (`build`, `normalize_credentials`,
    # `credential_change?`, `PENDING_PROVISION_STATUS`) so the callbacks
    # below can stay provider-agnostic instead of duplicating a near-copy of
    # this file for every new gateway.
    def gateway_provider_config_module(provider)
      {
        'evolution' => Custom::Whatsapp::Evolution::ProviderConfig,
        'evolution_go' => Custom::Whatsapp::EvolutionGo::ProviderConfig
      }[provider.to_s]
    end
  end

  def provider_service
    service = MessagingProvider::Registry.resolve(provider, whatsapp_channel: self)
    return service if service
    return super if provider.in?(%w[default whatsapp_cloud])

    # Any other provider is expected to resolve via the registry — falling
    # through to `super` here would silently dispatch through the 360dialog
    # upstream provider instead of failing loudly.
    Rails.logger.error("[MESSAGING_PROVIDER] provider_service could not resolve registry entry for provider=#{provider} channel=#{id}")
    raise "MessagingProvider::Registry has no service registered for '#{provider}' (channel #{id})"
  end

  def evolution_provider?
    provider == 'evolution'
  end

  def evolution_go_provider?
    provider == 'evolution_go'
  end

  def gateway_provider?
    self.class.gateway_provider_config_module(provider).present?
  end

  def dashboard_provider_config
    secret_keys = GATEWAY_SECRET_KEYS[provider]
    return provider_config if secret_keys.blank?

    config = (provider_config || {}).dup
    secret_keys.each { |key| config[key] = MASKED_SECRET if config[key].present? }
    config
  end

  def validate_provider_config
    return if gateway_provider? && !gateway_should_validate_credentials?

    super
  end

  private

  def gateway_should_validate_credentials?
    config_module = self.class.gateway_provider_config_module(provider)
    return false if (provider_config || {})['connection_status'] == config_module::PENDING_PROVISION_STATUS
    return true if new_record?

    return false unless provider_config_changed?

    config_module.credential_change?(provider_config_was, provider_config)
  end

  def sync_gateway_templates_noop
    mark_message_templates_updated
  end

  def sanitize_gateway_provider_config
    return unless provider_config_changed?

    config_module = self.class.gateway_provider_config_module(provider)
    previous = (provider_config_was || {}).stringify_keys
    incoming = (provider_config || {}).stringify_keys
    preserve_masked_secrets!(incoming, previous)

    merged = config_module.build(previous).merge(incoming)
    self.provider_config = config_module.normalize_credentials(merged)
  end

  def preserve_masked_secrets!(incoming, previous)
    (GATEWAY_SECRET_KEYS[provider] || []).each do |key|
      next unless incoming[key].blank? || incoming[key] == MASKED_SECRET

      incoming[key] = previous[key] if previous[key].present?
    end
  end

  def sync_evolution_provider_to_api
    return unless previous_changes.key?('provider_config')

    before_cfg, after_cfg = previous_changes['provider_config']
    synced_settings = Custom::Whatsapp::Evolution::ProviderConfig.settings_change?(before_cfg, after_cfg)
    synced_proxy = Custom::Whatsapp::Evolution::ProviderConfig.proxy_change?(before_cfg, after_cfg)
    return unless synced_settings || synced_proxy

    Custom::Whatsapp::Evolution::SyncProviderSettingsJob.perform_later(
      id,
      synced_settings: synced_settings,
      synced_proxy: synced_proxy
    )
  end

  def sync_evolution_go_provider_to_api
    return unless previous_changes.key?('provider_config')

    before_cfg, after_cfg = previous_changes['provider_config']
    changes = evolution_go_sync_changes(before_cfg, after_cfg)
    return unless changes.values.any?

    apply_evolution_go_sync!(changes)
  rescue Custom::Whatsapp::EvolutionGo::ApiError => e
    Rails.logger.error "[EVOLUTION_GO] settings sync failed for channel #{id}: #{e.message}"
    record_settings_sync_error!(e.message)
  end

  def evolution_go_sync_changes(before_cfg, after_cfg)
    {
      settings: Custom::Whatsapp::EvolutionGo::ProviderConfig.settings_change?(before_cfg, after_cfg),
      proxy: Custom::Whatsapp::EvolutionGo::ProviderConfig.proxy_change?(before_cfg, after_cfg),
      webhooks: Custom::Whatsapp::EvolutionGo::ProviderConfig.webhook_subscribe_change?(before_cfg, after_cfg)
    }
  end

  def apply_evolution_go_sync!(changes)
    service = Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: self)
    service.sync_settings! if changes[:settings]
    service.sync_proxy! if changes[:proxy]
    service.sync_webhook_subscribe! if changes[:webhooks]
    clear_settings_sync_error!
  end

  def clear_settings_sync_error!
    return if (provider_config || {})['settings_sync_error'].blank?

    config = (provider_config || {}).stringify_keys.except('settings_sync_error')
    # Intentionally skip validations — runtime metadata only
    update_column(:provider_config, config) # rubocop:disable Rails/SkipsModelValidations
  end

  def record_settings_sync_error!(message)
    config = (provider_config || {}).stringify_keys.merge('settings_sync_error' => message.to_s.truncate(500))
    update_column(:provider_config, config) # rubocop:disable Rails/SkipsModelValidations
  end

  def teardown_gateway_instance
    gateway_connection_service.teardown!
  rescue StandardError => e
    Rails.logger.warn "[#{provider.upcase}] destroy cleanup failed for channel #{id}: #{e.message}"
  end

  # Both gateway ConnectionServices use keyword `channel:` (attr_extras pattr_initialize).
  def gateway_connection_service
    case provider
    when 'evolution' then Custom::Whatsapp::Evolution::ConnectionService.new(channel: self)
    when 'evolution_go' then Custom::Whatsapp::EvolutionGo::ConnectionService.new(channel: self)
    end
  end
end

# rubocop:enable Metrics/ModuleLength
