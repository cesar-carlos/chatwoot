# frozen_string_literal: true

Rails.application.config.after_initialize do
  next unless ChatwootApp.custom?

  begin
    next unless ActiveRecord::Base.connection.table_exists?('installation_configs')

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
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
    # Database not ready yet (e.g. db:create / first migration on empty database).
  end
end
