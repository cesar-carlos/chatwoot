# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Llm::PdfProcessingService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:document) { create(:captain_document, account: account, assistant: assistant) }
  let(:client) { instance_double(OpenAI::Client) }

  before do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  it 'rebuilds the OpenAI client with the account hook key' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'system-key')

    expect(Custom::Llm::AccountCredential).to receive(:openai_client_for).with(account).and_return(client)

    service = described_class.new(document)
    expect(service.client).to eq(client)
  end

  it 'works when only the account hook key is present' do
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'hook-key' })

    expect(OpenAI::Client).to receive(:new).with(
      hash_including(access_token: 'hook-key')
    ).and_return(client)

    service = described_class.new(document)
    expect(service.client).to eq(client)
  end
end
