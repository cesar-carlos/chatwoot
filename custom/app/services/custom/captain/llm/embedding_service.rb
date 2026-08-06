# frozen_string_literal: true

# FORK: create embeddings with the account OpenAI hook key when available (BYOK).
module Custom::Captain::Llm::EmbeddingService
  def get_embedding(content, model: @embedding_model)
    return [] if content.blank?

    instrument_embedding_call(instrumentation_params(content, model)) do
      embed_with_account_credential(content, model)
    end
  rescue RubyLLM::Error => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise Captain::Llm::EmbeddingService::EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  def embed_with_account_credential(content, model)
    account = Account.find_by(id: @account_id) if @account_id.present?
    if account.present? && Custom::Llm::AccountCredential.resolve(account).present?
      _credential, context = Custom::Llm::AccountCredential.build_context(account)
      return context.embed(content, model: model).vectors
    end

    RubyLLM.embed(content, model: model).vectors
  end
end
