# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::ProviderConfig
  PENDING_PROVISION_STATUS = 'pending_provision'

  WEBHOOK_EVENTS = %w[
    MESSAGE
    SEND_MESSAGE
    CONNECTION
    QRCODE
    READ_RECEIPT
    MESSAGE_DELETE
    MESSAGES_DELETE
    MESSAGES_EDITED
    MESSAGE_EDIT
    HISTORY_SYNC
  ].freeze

  WEBHOOK_SUBSCRIBE_KEYS = %w[ignore_from_me_echo ignore_groups].freeze

  RUNTIME_KEYS = %w[
    connection_status
    last_qr_base64
    last_qr_code
    instance_id
    webhook_token
    webhook_subscribe
    settings_sync_error
  ].freeze

  CREDENTIAL_KEYS = %w[base_url global_api_key instance_token instance_name].freeze

  SETTINGS_KEYS = %w[
    ignore_groups
    reject_call
    msg_call
    always_online
    read_messages
    ignore_status
  ].freeze

  PROXY_KEYS = %w[
    proxy_enabled
    proxy_host
    proxy_port
    proxy_username
    proxy_password
  ].freeze

  SYNCABLE_KEYS = (SETTINGS_KEYS + PROXY_KEYS).freeze

  DEFAULTS = Custom::Whatsapp::EvolutionGo::ProviderConfigDefaults::DEFAULTS

  def self.build(attrs = {})
    normalize_credentials(DEFAULTS.merge(attrs.stringify_keys))
  end

  def self.normalize_credentials(config)
    config = config.stringify_keys
    %w[global_api_key instance_token instance_name].each do |key|
      config[key] = config[key].to_s.strip if config[key].present?
    end
    config['base_url'] = config['base_url'].to_s.strip.delete_suffix('/') if config['base_url'].present?
    config
  end

  def self.runtime_only?(attrs)
    attrs.stringify_keys.keys.all? { |key| RUNTIME_KEYS.include?(key) }
  end

  def self.credential_change?(before_config, after_config)
    before = (before_config || {}).stringify_keys
    after = (after_config || {}).stringify_keys
    CREDENTIAL_KEYS.any? { |key| before[key].to_s != after[key].to_s }
  end

  def self.settings_change?(before_config, after_config)
    config_changed?(before_config, after_config, SETTINGS_KEYS)
  end

  def self.proxy_change?(before_config, after_config)
    config_changed?(before_config, after_config, PROXY_KEYS)
  end

  def self.webhook_subscribe_change?(before_config, after_config)
    config_changed?(before_config, after_config, WEBHOOK_SUBSCRIBE_KEYS)
  end

  def self.config_changed?(before_config, after_config, keys)
    before = (before_config || {}).stringify_keys
    after = (after_config || {}).stringify_keys
    keys.any? { |key| before[key] != after[key] }
  end
end
