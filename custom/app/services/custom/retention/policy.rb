class Custom::Retention::Policy
  ENABLED_KEY = 'MESSAGE_ATTACHMENT_RETENTION_ENABLED'.freeze
  DAYS_KEY = 'MESSAGE_ATTACHMENT_RETENTION_DAYS'.freeze
  DISTRIBUTION_GROUPS_KEY = 'MESSAGE_ATTACHMENT_RETENTION_DISTRIBUTION_GROUPS'.freeze
  MAX_PURGE_PER_RUN_KEY = 'MESSAGE_ATTACHMENT_RETENTION_MAX_PURGE_PER_RUN'.freeze
  MAX_REENQUEUE_ATTEMPTS_KEY = 'MESSAGE_ATTACHMENT_RETENTION_MAX_REENQUEUE_ATTEMPTS'.freeze
  DRY_RUN_KEY = 'MESSAGE_ATTACHMENT_RETENTION_DRY_RUN'.freeze
  MAX_FAILURE_ATTEMPTS_KEY = 'MESSAGE_ATTACHMENT_RETENTION_MAX_FAILURE_ATTEMPTS'.freeze
  AUDIT_RETENTION_DAYS_KEY = 'MESSAGE_ATTACHMENT_RETENTION_AUDIT_RETENTION_DAYS'.freeze

  DEFAULT_RETENTION_DAYS = 90
  DEFAULT_DISTRIBUTION_GROUPS = 1
  DEFAULT_MAX_PURGE_PER_RUN = 2_000
  DEFAULT_MAX_REENQUEUE_ATTEMPTS = 100
  DEFAULT_MAX_FAILURE_ATTEMPTS = 3
  DEFAULT_AUDIT_RETENTION_DAYS = 365

  class << self
    def enabled?
      attachment_ttl.present?
    end

    def attachment_ttl
      return nil unless enabled_flag?

      days = retention_days
      return nil unless days.positive?

      days.days
    end

    def retention_days
      days_from_env || days_from_installation_config || DEFAULT_RETENTION_DAYS
    end

    def distribution_groups
      groups = ENV.fetch(DISTRIBUTION_GROUPS_KEY, DEFAULT_DISTRIBUTION_GROUPS).to_i
      groups.positive? ? groups : DEFAULT_DISTRIBUTION_GROUPS
    end

    def max_purge_per_run
      limit = ENV.fetch(MAX_PURGE_PER_RUN_KEY, DEFAULT_MAX_PURGE_PER_RUN).to_i
      limit.positive? ? limit : DEFAULT_MAX_PURGE_PER_RUN
    end

    def max_reenqueue_attempts
      limit = ENV.fetch(MAX_REENQUEUE_ATTEMPTS_KEY, DEFAULT_MAX_REENQUEUE_ATTEMPTS).to_i
      limit.positive? ? limit : DEFAULT_MAX_REENQUEUE_ATTEMPTS
    end

    def dry_run?
      return cast_boolean(ENV.fetch(DRY_RUN_KEY)) if ENV.key?(DRY_RUN_KEY)

      config_value = GlobalConfig.get(DRY_RUN_KEY)[DRY_RUN_KEY]
      return cast_boolean(config_value) unless config_value.nil?

      false
    end

    def max_failure_attempts
      limit = ENV.fetch(MAX_FAILURE_ATTEMPTS_KEY, DEFAULT_MAX_FAILURE_ATTEMPTS).to_i
      limit.positive? ? limit : DEFAULT_MAX_FAILURE_ATTEMPTS
    end

    def audit_retention_days
      days = ENV.fetch(AUDIT_RETENTION_DAYS_KEY, DEFAULT_AUDIT_RETENTION_DAYS).to_i
      days.positive? ? days : DEFAULT_AUDIT_RETENTION_DAYS
    end

    def eligible_attachments_scope
      Attachment
        .left_joins(:file_attachment)
        .where(
          'active_storage_attachments.id IS NOT NULL OR (attachments.external_url IS NOT NULL AND attachments.external_url != ?)',
          ''
        )
    end

    def expirable_attachments_scope(cutoff:, account_id: nil)
      scope = eligible_attachments_scope
              .where(attachments: { created_at: ...cutoff })
              .where.not(id: quarantined_attachment_ids(account_id: account_id))

      scope = scope.where(account_id: account_id) if account_id.present?
      scope
    end

    def quarantined_attachment_ids(account_id: nil)
      scope = AttachmentRetentionFailure.where('failure_count >= ?', max_failure_attempts)
      scope = scope.where(account_id: account_id) if account_id.present?
      scope.pluck(:attachment_id)
    end

    private

    def enabled_flag?
      return cast_boolean(ENV.fetch(ENABLED_KEY)) if ENV.key?(ENABLED_KEY)

      config_value = GlobalConfig.get(ENABLED_KEY)[ENABLED_KEY]
      return cast_boolean(config_value) unless config_value.nil?

      false
    end

    def days_from_env
      return unless ENV.key?(DAYS_KEY)

      ENV.fetch(DAYS_KEY).to_i
    end

    def days_from_installation_config
      config_value = GlobalConfig.get(DAYS_KEY)[DAYS_KEY]
      return if config_value.blank?

      config_value.to_i
    end

    def cast_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
