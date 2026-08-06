# frozen_string_literal: true

# FORK: paginated FAQ generation uses the same account OpenAI key as PDF upload (BYOK).
module Custom::Captain::Llm::PaginatedFaqGeneratorService
  def initialize(document, options = {})
    super
    rebuild_openai_client_for_account!(document.account)
  end
end
