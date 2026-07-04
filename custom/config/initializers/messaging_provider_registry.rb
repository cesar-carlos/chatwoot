# frozen_string_literal: true

Rails.application.config.after_initialize do
  MessagingProvider::Registry.register(
    'evolution',
    Custom::Whatsapp::Providers::EvolutionService
  )

  MessagingProvider::Registry.register(
    'evolution_go',
    Custom::Whatsapp::Providers::EvolutionGoService
  )
end
