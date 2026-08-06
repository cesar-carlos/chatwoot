# frozen_string_literal: true

# FORK: wrap Copilot / Assistant V1 chat completions with account-aware OpenAI credentials.
module Custom::Captain::ChatHelper
  def request_chat_completion
    with_account_llm_credential { super }
  end
end
