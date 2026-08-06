# frozen_string_literal: true

# FORK: Agents SDK Chat.new must see account OpenAI BYOK context (see Custom::Llm::ChatByok).
Rails.application.config.to_prepare do
  next unless ChatwootApp.custom?
  next if RubyLLM::Chat < Custom::Llm::ChatByok

  RubyLLM::Chat.prepend(Custom::Llm::ChatByok)
end
