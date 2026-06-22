# frozen_string_literal: true

module Custom::Whatsapp::Evolution::ProviderConfig
  IMPORT_STATUSES = %w[idle running completed failed].freeze
  IMPORT_PHASES = %w[contacts messages done].freeze

  PENDING_PROVISION_STATUS = 'pending_provision'

  WEBHOOK_EVENTS = %w[
    MESSAGES_UPSERT
    MESSAGES_UPDATE
    MESSAGES_DELETE
    MESSAGES_EDITED
    CONTACTS_UPSERT
    CONTACTS_UPDATE
    CONNECTION_UPDATE
    QRCODE_UPDATED
  ].freeze

  # Written by webhooks / connection polling — must not trigger Evolution API sync or credential validation.
  RUNTIME_KEYS = %w[
    connection_status
    last_qr_base64
    last_qr_code
    last_sender
    instance_id
    import_status
    import_cursor
    import_stats
    import_error
    import_started_at
    import_completed_at
    webhook_token
    settings_sync_error
  ].freeze

  EVOLUTION_SETTINGS_KEYS = %w[
    groups_ignore
    reject_call
    msg_call
    always_online
    read_messages
    read_status
    sync_full_history
  ].freeze

  PROXY_KEYS = %w[
    proxy_enabled
    proxy_host
    proxy_port
    proxy_protocol
    proxy_username
    proxy_password
  ].freeze

  # Pushed to Evolution via ConnectionService#sync_settings! / #sync_proxy!
  SYNCABLE_KEYS = (EVOLUTION_SETTINGS_KEYS + PROXY_KEYS).freeze

  CREDENTIAL_KEYS = %w[base_url api_key instance_name].freeze

  DEFAULTS = Custom::Whatsapp::Evolution::ProviderConfigDefaults::DEFAULTS

  def self.build(attrs = {})
    normalize_credentials(DEFAULTS.merge(attrs.stringify_keys))
  end

  def self.normalize_credentials(config)
    config = config.stringify_keys
    config['base_url'] = config['base_url'].to_s.strip.delete_suffix('/') if config['base_url'].present?
    config['api_key'] = config['api_key'].to_s.strip if config['api_key'].present?
    config['instance_name'] = config['instance_name'].to_s.strip if config['instance_name'].present?
    config
  end

  def self.runtime_only?(attrs)
    attrs.stringify_keys.keys.all? { |key| RUNTIME_KEYS.include?(key) }
  end

  def self.syncable_change?(before_config, after_config)
    settings_change?(before_config, after_config) || proxy_change?(before_config, after_config)
  end

  def self.settings_change?(before_config, after_config)
    config_changed?(before_config, after_config, EVOLUTION_SETTINGS_KEYS)
  end

  def self.proxy_change?(before_config, after_config)
    config_changed?(before_config, after_config, PROXY_KEYS)
  end

  def self.credential_change?(before_config, after_config)
    config_changed?(before_config, after_config, CREDENTIAL_KEYS)
  end

  def self.config_changed?(before_config, after_config, keys)
    before_config = (before_config || {}).stringify_keys
    after_config = (after_config || {}).stringify_keys
    keys.any? { |key| before_config[key] != after_config[key] }
  end
end
