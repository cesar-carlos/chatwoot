# frozen_string_literal: true

# FORK: Agents::Runner builds RubyLLM::Chat.new without a context, so Provider#initialize
# fails when CAPTAIN_OPEN_AI_API_KEY is blank. Inject the account BYOK context from
# Thread.current when Chat is created without an explicit context.
module Custom::Llm::ChatByok
  def initialize(model: nil, provider: nil, assume_model_exists: false, context: nil)
    context ||= Custom::Llm::AccountCredential.thread_context
    super(model: model, provider: provider, assume_model_exists: assume_model_exists, context: context)
  end
end
