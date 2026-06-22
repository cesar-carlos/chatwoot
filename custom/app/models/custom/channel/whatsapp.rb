# frozen_string_literal: true

module Custom::Channel::Whatsapp
  extend ActiveSupport::Concern

  MASKED_SECRET = '••••••••'

  prepended do
    after_commit :sync_evolution_templates_noop, on: :create, if: :evolution_provider?
    before_validation :sanitize_evolution_provider_config, on: :update, if: :evolution_provider?
    after_commit :sync_evolution_provider_to_api, on: :update, if: :evolution_provider?
    before_destroy :teardown_evolution_instance, if: :evolution_provider?
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

    merged = Custom::Whatsapp::Evolution::ProviderConfig.build(previous).merge(incoming)
    self.provider_config = Custom::Whatsapp::Evolution::ProviderConfig.normalize_credentials(merged)
  end

  def preserve_masked_secrets!(incoming, previous)
    %w[api_key proxy_password].each do |key|
      next unless incoming[key].blank? || incoming[key] == MASKED_SECRET

      incoming[key] = previous[key] if previous[key].present?
    end
  end

  def sync_evolution_provider_to_api
    return unless previous_changes.key?('provider_config')

    before_cfg, after_cfg = previous_changes['provider_config']
    service = Custom::Whatsapp::Evolution::ConnectionService.new(channel: self)
    service.sync_settings! if Custom::Whatsapp::Evolution::ProviderConfig.settings_change?(before_cfg, after_cfg)
    service.sync_proxy! if Custom::Whatsapp::Evolution::ProviderConfig.proxy_change?(before_cfg, after_cfg)
    clear_settings_sync_error!
  rescue Custom::Whatsapp::Evolution::ApiError => e
    Rails.logger.error "[EVOLUTION] settings sync failed for channel #{id}: #{e.message}"
    record_settings_sync_error!(e.message)
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

  def teardown_evolution_instance
    Custom::Whatsapp::Evolution::ConnectionService.new(channel: self).teardown!
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] destroy cleanup failed for channel #{id}: #{e.message}"
  end
end
