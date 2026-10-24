# frozen_string_literal: true

module Custom::NotificationSubscriptionBuilder
  def build_identifier_subscription
    super
    stamp_last_synced_at
  end

  def update_identifier_subscription
    super
    stamp_last_synced_at
  end

  private

  def stamp_last_synced_at
    record = identifier_subscription
    return unless record&.persisted?

    record.update_columns(last_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- sync time must not touch updated_at
  end
end
