# frozen_string_literal: true

module Custom::Whatsapp::Evolution::ProviderConfig
  DEFAULTS = {
    'groups_ignore' => true,
    'reject_call' => false,
    'msg_call' => '',
    'always_online' => false,
    'read_messages' => false,
    'read_status' => false,
    'sync_full_history' => false,
    'proxy_enabled' => false,
    'proxy_host' => '',
    'proxy_port' => '',
    'proxy_protocol' => 'http',
    'proxy_username' => '',
    'proxy_password' => '',
    'sign_msg' => false,
    'sign_delimiter' => "\n",
    'conversation_pending' => false,
    'merge_brazil_contacts' => true,
    'mark_read_on_reply' => false,
    'sync_delete_to_whatsapp' => false,
    'convert_markdown_outbound' => true,
    'convert_markdown_inbound' => true,
    'send_templates_as_text' => true,
    'send_random_delay' => true,
    'notify_send_errors_private' => true,
    'ignore_jids' => ['@g.us'],
    'ignore_status_broadcast' => true,
    'ignore_from_me_echo' => true,
    'ignore_survey_links' => true,
    'import_contacts' => false,
    'import_messages' => false,
    'days_limit_import_messages' => 7,
    'connection_status' => 'connecting',
    'import_status' => 'idle',
    'import_cursor' => {},
    'import_stats' => {},
    'import_error' => nil
  }.freeze

  IMPORT_STATUSES = %w[idle running completed failed].freeze
  IMPORT_PHASES = %w[contacts messages done].freeze

  PENDING_PROVISION_STATUS = 'pending_provision'

  WEBHOOK_EVENTS = %w[
    MESSAGES_UPSERT
    MESSAGES_UPDATE
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
  ].freeze

  # Pushed to Evolution via ConnectionService#sync_settings! / #sync_proxy!
  SYNCABLE_KEYS = %w[
    groups_ignore
    reject_call
    msg_call
    always_online
    read_messages
    read_status
    sync_full_history
    proxy_enabled
    proxy_host
    proxy_port
    proxy_protocol
    proxy_username
    proxy_password
  ].freeze

  CREDENTIAL_KEYS = %w[base_url api_key instance_name].freeze

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
    before_config = (before_config || {}).stringify_keys
    after_config = (after_config || {}).stringify_keys
    SYNCABLE_KEYS.any? { |key| before_config[key] != after_config[key] }
  end

  def self.credential_change?(before_config, after_config)
    before_config = (before_config || {}).stringify_keys
    after_config = (after_config || {}).stringify_keys
    CREDENTIAL_KEYS.any? { |key| before_config[key] != after_config[key] }
  end
end
