# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Conversation::ResponseBuilderJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    account.enable_features('captain_integration')
    account.disable_features('captain_integration_v2')

    allow_any_instance_of(described_class).to receive(:classify_v1_response_action) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:repair_v1_false_promise_response) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:capture_assistant_session) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Captain::Llm::AssistantChatService).to receive(:generate_response).and_return( # rubocop:disable RSpec/AnyInstance
      { 'response' => 'Hello from assistant', 'reasoning' => nil }
    )
  end

  it 'does not increment usage when the account OpenAI hook is present' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
    account.update!(custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 3))

    expect do
      described_class.perform_now(conversation, assistant)
    end.not_to(change { account.reload.custom_attributes['captain_responses_usage'].to_i })
  end

  it 'increments usage when using the system key' do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')
    account.update!(custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 3))

    expect do
      described_class.perform_now(conversation, assistant)
    end.to(change { account.reload.custom_attributes['captain_responses_usage'].to_i }.by(1))
  end
end
