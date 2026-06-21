# frozen_string_literal: true

Rails.application.config.after_initialize do
  MessagingProvider::Registry.register(
    'evolution',
    Custom::Whatsapp::Providers::EvolutionService
  )
end
