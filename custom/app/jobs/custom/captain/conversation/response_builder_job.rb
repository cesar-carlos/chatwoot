# frozen_string_literal: true

# FORK: skip captain_responses debit when the account OpenAI hook key is used (BYOK).
module Custom::Captain::Conversation::ResponseBuilderJob
  private

  def process_standard_response
    message = nil
    byok = Custom::Llm::AccountCredential.using_account_hook?(account)

    ActiveRecord::Base.transaction do
      next if captain_v2_enabled? && newer_customer_message_arrived?

      message = create_messages
      unless byok
        Rails.logger.info("[CAPTAIN][ResponseBuilderJob] Incrementing response usage for #{account.id}")
        account.increment_response_usage
      end
    end
    return unless message

    capture_assistant_session(result_message: message, credits_consumed: byok ? 0.0 : 1.0)
    record_v2_response_completed(message) if captain_v2_enabled?
  end
end
