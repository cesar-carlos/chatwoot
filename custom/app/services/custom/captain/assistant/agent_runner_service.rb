# frozen_string_literal: true

# FORK: bind Agents SDK chats to the account OpenAI hook key (BYOK).
# Agents::Runner builds Chat.new without context; with_account_context + ChatByok
# inject the keyed RubyLLM::Context before Provider#initialize runs.
module Custom::Captain::Assistant::AgentRunnerService
  def generate_response(message_history: [])
    Custom::Llm::AccountCredential.with_account_context(@assistant.account) do |credential, context|
      @llm_credential = credential
      @llm_ruby_context = context
      super
    end
  end
end
