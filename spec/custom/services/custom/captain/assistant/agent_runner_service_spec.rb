# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Assistant::AgentRunnerService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:mock_runner) { double('Agents::AgentRunner') } # rubocop:disable RSpec/VerifiedDoubles
  let(:run_result) do
    double( # rubocop:disable RSpec/VerifiedDoubles
      'RunResult',
      output: { 'response' => 'Hello', 'reasoning' => nil },
      context: { conversation_history: [], state: {}, session_id: 's1' },
      messages: [],
      failed?: false,
      error: nil
    )
  end
  let(:mock_context) { instance_double(RubyLLM::Context) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    allow_any_instance_of(described_class).to receive(:build_and_wire_agents).and_return([]) # rubocop:disable RSpec/AnyInstance
    allow(Agents::Runner).to receive(:with_agents).and_return(mock_runner)
    allow(mock_runner).to receive(:run).and_return(run_result)
    allow_any_instance_of(described_class).to receive(:add_usage_metadata_callback) { |_, runner| runner } # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:install_instrumentation) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:record_turn_start) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:response_too_long?).and_return(false) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:process_agent_result) do |_instance, result| # rubocop:disable RSpec/AnyInstance
      result.output
    end

    allow(RubyLLM).to receive(:context) do |&block|
      config = instance_double('config').as_null_object # rubocop:disable RSpec/VerifiedDoubleReference
      block&.call(config)
      mock_context
    end
  end

  after do
    Thread.current[Custom::Llm::AccountCredential::THREAD_CONTEXT_KEY] = nil
  end

  it 'sets the account OpenAI RubyLLM context on the thread for Agents Chat.new' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

    expect(mock_runner).to receive(:run) do
      expect(Custom::Llm::AccountCredential.thread_context).to eq(mock_context)
      run_result
    end

    described_class.new(assistant: assistant, source: 'playground')
                   .generate_response(message_history: [{ role: 'user', content: 'hi' }])

    expect(Custom::Llm::AccountCredential.thread_context).to be_nil
  end

  it 'raises when no OpenAI key is configured' do
    expect do
      described_class.new(assistant: assistant, source: 'playground')
                     .generate_response(message_history: [{ role: 'user', content: 'hi' }])
    end.to raise_error(StandardError, I18n.t('captain.api_key_missing'))
  end
end
