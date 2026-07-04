# frozen_string_literal: true

Rails.application.config.to_prepare do
  path = Rails.root.join('custom/app/controllers/custom/api/v1/accounts/conversations_controller.rb')
  require path.to_s if path.exist?
end
