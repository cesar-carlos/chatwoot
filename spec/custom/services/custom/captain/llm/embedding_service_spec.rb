# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Llm::EmbeddingService do
  let(:account) { create(:account) }
  let(:mock_context) { instance_double(RubyLLM::Context) }
  let(:mock_embedding) { instance_double(RubyLLM::Embedding, vectors: [0.1, 0.2]) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    allow(RubyLLM).to receive(:context) do |&block|
      config = instance_double('config').as_null_object # rubocop:disable RSpec/VerifiedDoubleReference
      block&.call(config)
      mock_context
    end
  end

  it 'embeds with the account OpenAI hook context when account_id is present' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
    expect(mock_context).to receive(:embed).with('hello', model: kind_of(String)).and_return(mock_embedding)
    expect(RubyLLM).not_to receive(:embed)

    result = described_class.new(account_id: account.id).get_embedding('hello')
    expect(result).to eq([0.1, 0.2])
  end

  it 'falls back to global RubyLLM.embed when account_id is blank' do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')
    expect(RubyLLM).to receive(:embed).with('hello', model: kind_of(String)).and_return(mock_embedding)

    result = described_class.new.get_embedding('hello')
    expect(result).to eq([0.1, 0.2])
  end
end
