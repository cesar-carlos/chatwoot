# frozen_string_literal: true

# FORK: bind response rewriter Agents chats to the account OpenAI hook key (BYOK).
module Custom::Captain::Assistant::ResponseRewriter
  def rewrite(result, response:, limit:)
    Custom::Llm::AccountCredential.with_account_context(@assistant.account) do |credential, context|
      @llm_credential = credential
      @llm_ruby_context = context
      super
    end
  end
end
