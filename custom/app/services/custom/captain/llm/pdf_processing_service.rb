# frozen_string_literal: true

# FORK: PDF upload uses the same account OpenAI key as paginated FAQ generation (BYOK).
module Custom::Captain::Llm::PdfProcessingService
  def initialize(document)
    super
    rebuild_openai_client_for_account!(document.account)
  end
end
