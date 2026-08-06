# frozen_string_literal: true

# FORK: Captain stays active when the account brings its own OpenAI key (BYOK),
# even if installation captain_responses quota is exhausted.
module Custom::Inbox
  private

  def more_responses?
    return true if Custom::Llm::AccountCredential.using_account_hook?(account)

    super
  end
end
