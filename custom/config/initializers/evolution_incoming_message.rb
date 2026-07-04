# frozen_string_literal: true

# FORK: ensure Evolution prepends on IncomingMessageBaseService load in all environments
Rails.application.config.to_prepare do
  %w[
    incoming_message_base_service
    incoming_message_service_helpers
    incoming_message_identifier_helper
    incoming_message_evolution_go
  ].each do |file|
    path = Rails.root.join("custom/app/services/custom/whatsapp/#{file}.rb")
    require path.to_s if path.exist?
  end
end
