# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Whatsapp::EvolutionGo::DiagnosticsService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'evolution_go',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: Custom::Whatsapp::EvolutionGo::ProviderConfig.build(
        'base_url' => 'https://go.example.com',
        'global_api_key' => 'global-key',
        'instance_token' => 'instance-token',
        'instance_name' => 'test-instance',
        'instance_id' => 'inst-1',
        'webhook_token' => 'hook-secret'
      )
    )
  end
  let(:api_client) { instance_double(Custom::Whatsapp::EvolutionGo::ApiClient) }

  before do
    allow(Custom::Whatsapp::EvolutionGo::ApiClient).to receive(:for_channel).and_return(api_client)
    allow(api_client).to receive(:instance_info).and_return(
      instance_double(HTTParty::Response, success?: true)
    )
    allow(api_client).to receive(:unwrap).and_return(
      'name' => 'test-instance',
      'token' => 'instance-secret',
      'webhookUrl' => 'https://chat.example/webhooks/evolution_go/test?token=abc'
    )
    allow(api_client).to receive(:instance_logs).and_return(
      instance_double(
        HTTParty::Response,
        success?: true,
        parsed_response: { 'data' => [{ 'message' => 'ok', 'apikey' => 'hidden' }] }
      )
    )
  end

  around do |example|
    ClimateControl.modify(FRONTEND_URL: 'https://chatwoot.example.com') { example.run }
  end

  it 'drops instance tokens and keeps the operator webhook URL' do
    payload = described_class.new(channel: channel).perform

    expect(payload[:webhook_url]).to include('token=hook-secret')
    expect(payload[:instance_info]).to eq(
      'name' => 'test-instance',
      'webhookUrl' => 'https://chat.example/webhooks/evolution_go/test?token=[redacted]'
    )
    expect(payload[:instance_logs]).to eq([{ 'message' => 'ok' }])
  end
end
