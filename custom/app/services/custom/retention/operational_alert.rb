class Custom::Retention::OperationalAlert
  SENTRY_ENVIRONMENTS = %w[production staging].freeze

  class << self
    def reenqueue_limit_reached(account_id:, attempt:, purge_result:)
      payload = {
        component: 'Custom::Retention::PurgeAccountAttachmentsJob',
        event: 'reenqueue_limit_reached',
        account_id: account_id,
        attempt: attempt,
        deleted_count: purge_result[:deleted_count],
        failed_count: purge_result[:failed_count],
        has_more: purge_result[:has_more]
      }

      Rails.logger.warn(payload.to_json)
      capture_sentry_warning(account_id, attempt, purge_result) if sentry_reporting_enabled?
    end

    private

    def sentry_reporting_enabled?
      ENV['SENTRY_DSN'].present? &&
        defined?(Sentry) &&
        SENTRY_ENVIRONMENTS.include?(Rails.env.to_s)
    end

    def capture_sentry_warning(account_id, attempt, purge_result)
      Sentry.with_scope do |scope|
        scope.set_tags(account_id: account_id)
        scope.set_context('retention_purge', purge_result.merge(attempt: attempt))
        Sentry.capture_message(
          'Message attachment retention reenqueue limit reached',
          level: :warning
        )
      end
    end
  end
end
