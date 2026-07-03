class BackfillEnabledFeaturesDataOnAccounts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    Account.reset_column_information
    return unless Account.column_names.include?('enabled_features_data')

    Account.find_each(batch_size: 100) do |account|
      Accounts::FeatureStore.new(account).backfill_from_bitmask!
      # rubocop:disable Rails/SkipsModelValidations
      account.update_columns(
        enabled_features_data: account.enabled_features_data,
        updated_at: Time.current
      )
      # rubocop:enable Rails/SkipsModelValidations
    end
  end
end
