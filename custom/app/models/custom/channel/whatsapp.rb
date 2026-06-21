# frozen_string_literal: true

module Custom::Channel::Whatsapp
  extend ActiveSupport::Concern

  MASKED_SECRET = '••••••••'

  prepended do
    after_commit :sync_evolution_templates_noop, on: :create, if: :evolution_provider?
    before_validation :sanitize_evolution_provider_config, on: :update, if: :evolution_provider?
    after_commit :sync_evolution_provider_to_api, on: :update, if: :evolution_provider?
  end

  def provider_service
    service = MessagingProvider::Registry.resolve(provider, whatsapp_channel: self)
    return service if service

    super
  end

  def evolution_provider?
    provider == 'evolution'
  end

  def dashboard_provider_config
    return provider_config unless evolution_provider?

    config = (provider_config || {}).dup
    config['api_key'] = MASKED_SECRET if config['api_key'].present?
    config['proxy_password'] = MASKED_SECRET if config['proxy_password'].present?
    config
  end

  def validate_provider_config
    return if evolution_provider? && !evolution_should_validate_credentials?

    super
  end

  private

  def evolution_should_validate_credentials?
    return false if (provider_config || {})['connection_status'] == Custom::Whatsapp::Evolution::ProviderConfig::PENDING_PROVISION_STATUS
    return true if new_record?

    return false unless provider_config_changed?

    Custom::Whatsapp::Evolution::ProviderConfig.credential_change?(
      provider_config_was,
      provider_config
    )
  end

  def sync_evolution_templates_noop
    mark_message_templates_updated
  end

  def sanitize_evolution_provider_config
    return unless provider_config_changed?

    previous = (provider_config_was || {}).stringify_keys
    incoming = (provider_config || {}).stringify_keys
    preserve_masked_secrets!(incoming, previous)

    self.provider_config = Custom::Whatsapp::Evolution::ProviderConfig.build(previous).merge(incoming)
  end

  def preserve_masked_secrets!(incoming, previous)
    %w[api_key proxy_password].each do |key|
      next unless incoming[key].blank? || incoming[key] == MASKED_SECRET

      incoming[key] = previous[key] if previous[key].present?
    end
  end

  def sync_evolution_provider_to_api
    return unless previous_changes.key?('provider_config')
    return unless evolution_syncable_settings_changed?

    service = Custom::Whatsapp::Evolution::ConnectionService.new(self)
    service.sync_settings!
    service.sync_proxy!
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] settings sync failed for channel #{id}: #{e.message}"
  end

  def evolution_syncable_settings_changed?
    before_cfg, after_cfg = previous_changes['provider_config']
    Custom::Whatsapp::Evolution::ProviderConfig.syncable_change?(before_cfg, after_cfg)
  end
end

Channel::Whatsapp.prepend_mod_with('Channel::Whatsapp')
