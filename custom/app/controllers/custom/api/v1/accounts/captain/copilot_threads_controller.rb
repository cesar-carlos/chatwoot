# frozen_string_literal: true

# FORK: allow new Copilot threads when the account uses its own OpenAI hook (BYOK).
module Custom::Api::V1::Accounts::Captain::CopilotThreadsController
  private

  def build_copilot_response(copilot_message)
    if captain_responses_available? || Custom::Llm::AccountCredential.using_account_hook?(Current.account)
      copilot_message.enqueue_response_job(copilot_thread_params[:conversation_id], Current.user.id)
    else
      copilot_message.copilot_thread.copilot_messages.create!(
        message_type: :assistant,
        message: { content: I18n.t('captain.copilot_limit') }
      )
    end
  end

  def captain_responses_available?
    Current.account.usage_limits[:captain][:responses][:current_available].positive?
  end
end
