# frozen_string_literal: true

# Seeds VOICE_CALL_STUN_URLS as an editable Super Admin installation config.
Rails.application.config.after_initialize do
  InstallationConfig.find_or_create_by!(name: 'VOICE_CALL_STUN_URLS') do |config|
    config.value = 'stun:stun.l.google.com:19302'
    config.locked = false
  end
rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
  # DB not ready during certain rake tasks
end
