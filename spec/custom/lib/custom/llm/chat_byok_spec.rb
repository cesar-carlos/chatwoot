# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Llm::ChatByok do
  after do
    Thread.current[Custom::Llm::AccountCredential::THREAD_CONTEXT_KEY] = nil
  end

  it 'is prepended onto RubyLLM::Chat' do
    expect(RubyLLM::Chat.ancestors).to include(described_class)
  end

  it 'injects the thread BYOK context when Chat.new has no explicit context' do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')
    _credential, context = Custom::Llm::AccountCredential.build_context(nil)
    Thread.current[Custom::Llm::AccountCredential::THREAD_CONTEXT_KEY] = context

    chat = RubyLLM::Chat.new(model: Llm::Config::DEFAULT_MODEL)
    expect(chat.instance_variable_get(:@context)).to eq(context)
    expect(chat.instance_variable_get(:@config).openai_api_key).to eq('system-key')
  end
end
