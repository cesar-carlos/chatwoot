# frozen_string_literal: true

module Custom::Whatsapp::EvolutionGo::EventNames
  module_function

  # Evolution Go webhooks use PascalCase (`Message`, `SendMessage`); fork handlers
  # expect SCREAMING_SNAKE (`MESSAGE`, `SEND_MESSAGE`).
  def normalize(event)
    token = event.to_s.tr('.', '_')
    token = token.gsub(/([a-z\d])([A-Z])/, '\1_\2') if token.match?(/[a-z][A-Z]/)
    token.upcase
  end
end
