class AddEnabledFeaturesDataToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :enabled_features_data, :jsonb, null: false, default: {}
  end
end
