# frozen_string_literal: true

class Custom::Notification::PushDeliveryRecorder
  STATUSES = %w[accepted failed expired].freeze
  ERROR_LIMIT = 255

  def self.record(subscription, status:, error: nil)
    return unless STATUSES.include?(status)
    return unless subscription&.persisted?

    subscription.update_columns( # rubocop:disable Rails/SkipsModelValidations -- delivery metadata must not touch updated_at
      last_push_at: Time.current,
      last_push_status: status,
      last_push_error: error_summary(error)
    )
  end

  def self.error_summary(error)
    summary = Custom::Notification::BrowserPushLogContext.error_summary(error)
    summary&.truncate(ERROR_LIMIT, omission: '')
  end
end
