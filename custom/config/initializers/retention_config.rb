# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless ChatwootApp.custom?

  InstallationConfig.find_or_create_by!(name: Custom::Retention::Policy::DAYS_KEY) do |config|
    config.value = '90'
    config.locked = false
  end

  InstallationConfig.find_or_create_by!(name: Custom::Retention::Policy::ENABLED_KEY) do |config|
    config.value = 'false'
    config.locked = false
  end

  InstallationConfig.find_or_create_by!(name: Custom::Retention::Policy::DRY_RUN_KEY) do |config|
    config.value = 'false'
    config.locked = false
  end
end
