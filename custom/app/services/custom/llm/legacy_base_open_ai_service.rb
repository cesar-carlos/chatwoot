# frozen_string_literal: true

# FORK: allow account OpenAI hook (BYOK) for legacy PDF/file clients.
# PdfProcessing / PaginatedFaq overlays rebuild the client with the account key after init.
module Custom::Llm::LegacyBaseOpenAiService
  def initialize
    setup_model
    system = Custom::Llm::AccountCredential.resolve(nil)
    @client = build_openai_client(system[:api_key]) if system
  rescue StandardError => e
    raise "Failed to initialize OpenAI client: #{e.message}"
  end

  def rebuild_openai_client_for_account!(account)
    @client = Custom::Llm::AccountCredential.openai_client_for(account)
  end

  private

  def build_openai_client(access_token)
    OpenAI::Client.new(
      access_token: access_token,
      uri_base: uri_base,
      log_errors: Rails.env.development?
    )
  end
end
