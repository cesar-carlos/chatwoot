# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Llm::FaqGeneratorService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:document) do
    create(:captain_document, account: account, assistant: assistant, content: 'Product returns are accepted within 30 days.')
  end
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_context) { instance_double(RubyLLM::Context) }
  let(:mock_response) do
    instance_double(RubyLLM::Message, content: '{"faqs":[{"question":"Q?","answer":"A"}]}')
  end

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    allow(RubyLLM).to receive(:context) do |&block|
      config = instance_double('config').as_null_object # rubocop:disable RSpec/VerifiedDoubleReference
      block&.call(config)
      mock_context
    end
    allow(mock_context).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  it 'uses the account OpenAI context for FAQ generation' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
    expect(mock_context).to receive(:chat).with(model: kind_of(String)).and_return(mock_chat)
    expect(RubyLLM).not_to receive(:chat)

    faqs = described_class.new(document: document).generate
    expect(faqs).to be_an(Array)
  end
end
