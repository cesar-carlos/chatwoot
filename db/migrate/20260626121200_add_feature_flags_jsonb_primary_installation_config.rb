class AddFeatureFlagsJsonbPrimaryInstallationConfig < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_or_initialize_by(name: 'FEATURE_FLAGS_JSONB_PRIMARY')
    config.value = false
    config.save!
    GlobalConfig.clear_cache
  end

  def down
    InstallationConfig.find_by(name: 'FEATURE_FLAGS_JSONB_PRIMARY')&.destroy
    GlobalConfig.clear_cache
  end
end
