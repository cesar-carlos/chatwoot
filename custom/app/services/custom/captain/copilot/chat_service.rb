# frozen_string_literal: true

# FORK: do not debit captain_responses when the account OpenAI hook key is used.
module Custom::Captain::Copilot::ChatService
  def generate_response(input)
    @messages << { role: 'user', content: input } if input.present?
    response = request_chat_completion

    if counts_toward_captain_usage?
      Rails.logger.info(
        "#{self.class.name} Assistant: #{@assistant.id}, Incrementing response usage for account #{@account.id}"
      )
      @account.increment_response_usage
    else
      Rails.logger.info(
        "#{self.class.name} Assistant: #{@assistant.id}, Skipping response usage for account #{@account.id} (OpenAI hook)"
      )
    end

    response
  end

  private

  def counts_toward_captain_usage?
    llm_credential&.dig(:source) != :hook
  end
end
