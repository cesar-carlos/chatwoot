# frozen_string_literal: true

# FORK: run RubyLLM chats with account OpenAI hook key (BYOK) when available.
module Custom::Llm::BaseAiService
  def chat(model: @model, temperature: @temperature, thinking: nil, feature: @llm_feature, **)
    options = Captain::ResponsesConfig.options(model: model, temperature: temperature, feature: feature)
    thinking ||= options[:thinking]
    context = @llm_ruby_context || account_ruby_llm_context
    llm_chat = if context
                 # FORK: account OpenAI BYOK uses a keyed RubyLLM context
                 context.chat(model: model, **options.slice(:protocol), **)
               else
                 RubyLLM.chat(model: model, **options.slice(:protocol), **)
               end
    llm_chat.with_thinking(**thinking) if thinking
    return llm_chat if options[:temperature].nil? || (thinking && thinking[:effort] != :none)

    llm_chat.with_temperature(options[:temperature])
  end

  def llm_credential
    @llm_credential
  end

  private

  def with_account_llm_credential
    @llm_credential, context = Custom::Llm::AccountCredential.build_context(llm_account_for_credential)
    previous_context = @llm_ruby_context
    @llm_ruby_context = context
    yield
  ensure
    @llm_ruby_context = previous_context
  end

  def account_ruby_llm_context
    account = llm_account_for_credential
    return if account.blank?

    @llm_credential, context = Custom::Llm::AccountCredential.build_context(account)
    context
  end

  def llm_account_for_credential
    @account || @llm_account || @assistant&.account
  end
end
